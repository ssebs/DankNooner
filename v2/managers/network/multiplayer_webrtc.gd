class_name MultiplayerWebRTC extends Node

## WebRTC multiplayer handler with embedded signaling server.
## The host runs a WebSocket signaling server; clients connect to it.
## Follows the same interface as MultiplayerIPPort and MultiplayerNoray.

signal connection_failed(reason: String)
signal connection_succeeded(peer_id: int)

enum Message {
	JOIN,
	ID,
	PEER_CONNECT,
	PEER_DISCONNECT,
	OFFER,
	ANSWER,
	CANDIDATE,
	SEAL,
}

## Port for the embedded WebSocket signaling server
@export var signaling_port: int = 9080

## STUN/TURN server URL for ICE negotiation
@export var stun_server: String = "stun:stun.ssebs.com:3478"

## Optional TURN server URL (for relay fallback behind symmetric NAT)
@export var turn_server: String = ""
@export var turn_username: String = ""
@export var turn_credential: String = ""

var _lobby_code: String = ""
var _ws := WebSocketPeer.new()
var _ws_old_state := WebSocketPeer.STATE_CLOSED
var _rtc_mp := WebRTCMultiplayerPeer.new()
var _is_server: bool = false
var _peer_ready: bool = false
var _signaling_url: String = ""

# Embedded signaling server state
var _tcp_server := TCPServer.new()
var _sig_peers: Dictionary = {}  # id -> SignalingPeer
var _sig_lobby := {}  # lobby_code -> SignalingLobby
var _sig_rand := RandomNumberGenerator.new()
var _server_ip: String = ""

const ALFNUM = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
const SIG_TIMEOUT = 10000
const SEAL_TIME = 10000

#region Signaling server internals


class SignalingPeer:
	extends RefCounted
	var id := -1
	var lobby: String = ""
	var time := Time.get_ticks_msec()
	var ws := WebSocketPeer.new()

	func _init(peer_id: int, tcp: StreamPeer) -> void:
		id = peer_id
		ws.accept_stream(tcp)

	func is_ws_open() -> bool:
		return ws.get_ready_state() == WebSocketPeer.STATE_OPEN

	func send(type: int, send_id: int, data: String = "") -> void:
		(
			ws
			. send_text(
				(
					JSON
					. stringify(
						{
							"type": type,
							"id": send_id,
							"data": data,
						}
					)
				)
			)
		)


class SignalingLobby:
	extends RefCounted
	var peers := {}
	var host := -1
	var sealed: bool = false
	var time := 0

	func _init(host_id: int) -> void:
		host = host_id

	func join(peer: SignalingPeer) -> bool:
		if sealed:
			return false
		if not peer.is_ws_open():
			return false
		# Client-server mode: host gets ID 1, others keep their ID
		peer.send(Message.ID, 1 if peer.id == host else peer.id, "")
		for p: SignalingPeer in peers.values():
			if not p.is_ws_open():
				continue
			# Only host is visible in client-server mode
			if p.id != host:
				continue
			p.send(Message.PEER_CONNECT, peer.id)
			peer.send(Message.PEER_CONNECT, 1 if p.id == host else p.id)
		peers[peer.id] = peer
		return true

	func leave(peer: SignalingPeer) -> bool:
		if not peers.has(peer.id):
			return false
		peers.erase(peer.id)
		var close: bool = false
		if peer.id == host:
			close = true
		if sealed:
			return close
		for p: SignalingPeer in peers.values():
			if not p.is_ws_open():
				continue
			if close:
				p.ws.close()
			else:
				p.send(Message.PEER_DISCONNECT, peer.id)
		return close

	func seal(peer_id: int) -> bool:
		if host != peer_id:
			return false
		sealed = true
		for p: SignalingPeer in peers.values():
			if not p.is_ws_open():
				continue
			p.send(Message.SEAL, 0)
		time = Time.get_ticks_msec()
		peers.clear()
		return true


func _start_signaling_server() -> Error:
	_sig_rand.seed = int(Time.get_unix_time_from_system())
	var err = _tcp_server.listen(signaling_port)
	if err != OK:
		printerr("WebRTC: failed to start signaling server on port %d" % signaling_port)
		return err
	print("WebRTC: signaling server listening on port %d" % signaling_port)
	return OK


func _stop_signaling_server() -> void:
	_tcp_server.stop()
	_sig_peers.clear()
	_sig_lobby.clear()


func _poll_signaling_server() -> void:
	if not _tcp_server.is_listening():
		return

	if _tcp_server.is_connection_available():
		var id := randi() % (1 << 31)
		_sig_peers[id] = SignalingPeer.new(id, _tcp_server.take_connection())

	var to_remove := []
	for p: SignalingPeer in _sig_peers.values():
		if p.lobby.is_empty() and Time.get_ticks_msec() - p.time > SIG_TIMEOUT:
			p.ws.close()
		p.ws.poll()
		while p.is_ws_open() and p.ws.get_available_packet_count():
			if not _sig_parse_msg(p):
				to_remove.push_back(p.id)
				p.ws.close()
				break
		var state := p.ws.get_ready_state()
		if state == WebSocketPeer.STATE_CLOSED:
			if _sig_lobby.has(p.lobby) and _sig_lobby[p.lobby].leave(p):
				_sig_lobby.erase(p.lobby)
			to_remove.push_back(p.id)

	for k: String in _sig_lobby:
		if not _sig_lobby[k].sealed:
			continue
		if _sig_lobby[k].time + SEAL_TIME < Time.get_ticks_msec():
			for p: SignalingPeer in _sig_lobby[k].peers.values():
				p.ws.close()
				to_remove.push_back(p.id)

	for id: int in to_remove:
		_sig_peers.erase(id)


func _sig_join_lobby(peer: SignalingPeer, lobby: String) -> bool:
	if lobby.is_empty():
		for _i in 32:
			lobby += char(ALFNUM.to_ascii_buffer()[_sig_rand.randi_range(0, ALFNUM.length() - 1)])
		_sig_lobby[lobby] = SignalingLobby.new(peer.id)
	elif not _sig_lobby.has(lobby):
		return false
	_sig_lobby[lobby].join(peer)
	peer.lobby = lobby
	peer.send(Message.JOIN, 0, lobby)
	print("WebRTC signaling: peer %d joined lobby '%s'" % [peer.id, lobby])
	return true


func _sig_parse_msg(peer: SignalingPeer) -> bool:
	var pkt_str: String = peer.ws.get_packet().get_string_from_utf8()
	var parsed: Dictionary = JSON.parse_string(pkt_str)
	if (
		typeof(parsed) != TYPE_DICTIONARY
		or not parsed.has("type")
		or not parsed.has("id")
		or typeof(parsed.get("data")) != TYPE_STRING
	):
		return false
	if parsed.type is not float or parsed.id is not float:
		return false

	var msg := {
		"type": str(parsed.type).to_int(),
		"id": str(parsed.id).to_int(),
		"data": parsed.data,
	}

	if msg.type == Message.JOIN:
		if peer.lobby:
			return false
		return _sig_join_lobby(peer, msg.data)

	if not _sig_lobby.has(peer.lobby):
		return false

	var lobby: SignalingLobby = _sig_lobby[peer.lobby]

	if msg.type == Message.SEAL:
		return lobby.seal(peer.id)

	var dest_id: int = msg.id
	if dest_id == MultiplayerPeer.TARGET_PEER_SERVER:
		dest_id = lobby.host

	if not _sig_peers.has(dest_id):
		return false
	if _sig_peers[dest_id].lobby != peer.lobby:
		return false

	if msg.type in [Message.OFFER, Message.ANSWER, Message.CANDIDATE]:
		var source := MultiplayerPeer.TARGET_PEER_SERVER if peer.id == lobby.host else peer.id
		_sig_peers[dest_id].send(msg.type, source, msg.data)
		return true

	return false


#endregion

#region Public API (handler interface)


## Starts the embedded signaling server, then connects to it as the host.
## Returns the WebRTCMultiplayerPeer once ready.
func start_server() -> MultiplayerPeer:
	_is_server = true
	_peer_ready = false
	_lobby_code = ""

	# Start embedded signaling server
	var err := _start_signaling_server()
	if err != OK:
		return null

	# Fetch our IP so clients know where to connect
	_server_ip = await _get_public_ip_addr()

	# Connect to our own signaling server as a WebSocket client
	_signaling_url = "ws://127.0.0.1:%d" % signaling_port
	_ws.connect_to_url(_signaling_url)

	# Poll until we get our ID and the peer is created
	while not _peer_ready:
		await get_tree().process_frame
		_poll_signaling_server()
		_poll_ws()

	return _rtc_mp


func stop_server():
	_stop_signaling_server()
	_cleanup()


## Joins an existing lobby by code via the signaling server.
## Address format: "ip:lobby_code" (e.g. "192.168.1.5:ABCxyz123")
func connect_client(address: String) -> Error:
	_is_server = false
	_peer_ready = false

	# Parse address — "ip:lobby_code"
	var colon_idx := address.find(":")
	if colon_idx == -1:
		connection_failed.emit("Invalid address format. Expected 'ip:lobby_code'")
		return ERR_INVALID_PARAMETER

	var host_ip := address.substr(0, colon_idx)
	_lobby_code = address.substr(colon_idx + 1)

	_signaling_url = "ws://%s:%d" % [host_ip, signaling_port]
	_ws.connect_to_url(_signaling_url)

	# Poll until we get our ID and the peer is created
	while not _peer_ready:
		await get_tree().process_frame
		_poll_ws()

	multiplayer.multiplayer_peer = _rtc_mp
	connection_succeeded.emit(_rtc_mp.get_unique_id())
	return OK


func disconnect_client():
	_cleanup()


## Returns the address clients need to join: "ip:lobby_code"
func get_addr() -> String:
	if _server_ip.is_empty() or _lobby_code.is_empty():
		return ""
	return "%s:%s" % [_server_ip, _lobby_code]


#endregion

#region WebSocket polling & signaling client


func _process(_delta: float) -> void:
	if _is_server:
		_poll_signaling_server()
	_poll_ws()


func _poll_ws() -> void:
	_ws.poll()
	var state := _ws.get_ready_state()

	# On first open, join/create lobby
	if state != _ws_old_state and state == WebSocketPeer.STATE_OPEN:
		# id=1 means client-server mode (not mesh)
		_send_msg(Message.JOIN, 1, _lobby_code)

	# Parse incoming messages
	while state == WebSocketPeer.STATE_OPEN and _ws.get_available_packet_count():
		if not _parse_msg():
			printerr("WebRTC signaling: failed to parse message")

	# Handle disconnect
	if state != _ws_old_state and state == WebSocketPeer.STATE_CLOSED:
		if not _peer_ready:
			connection_failed.emit("Signaling server disconnected")

	_ws_old_state = state


func _parse_msg() -> bool:
	var parsed: Dictionary = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
	if (
		typeof(parsed) != TYPE_DICTIONARY
		or not parsed.has("type")
		or not parsed.has("id")
		or typeof(parsed.get("data")) != TYPE_STRING
	):
		return false

	var type := int(parsed.type)
	var src_id := int(parsed.id)
	var data: String = parsed.data

	match type:
		Message.ID:
			_on_id_received(src_id, data == "true")
		Message.JOIN:
			_lobby_code = data
			print("WebRTC: joined lobby '%s'" % _lobby_code)
		Message.SEAL:
			pass
		Message.PEER_CONNECT:
			_on_peer_connected(src_id)
		Message.PEER_DISCONNECT:
			_on_peer_disconnected(src_id)
		Message.OFFER:
			_on_offer_received(src_id, data)
		Message.ANSWER:
			_on_answer_received(src_id, data)
		Message.CANDIDATE:
			var parts: PackedStringArray = data.split("\n", false)
			if parts.size() != 3 or not parts[1].is_valid_int():
				return false
			_on_candidate_received(src_id, parts[0], parts[1].to_int(), parts[2])
		_:
			return false

	return true


func _send_msg(type: int, id: int, data: String = "") -> Error:
	return (
		_ws
		. send_text(
			(
				JSON
				. stringify(
					{
						"type": type,
						"id": id,
						"data": data,
					}
				)
			)
		)
	)


#endregion

#region WebRTC peer management


func _get_ice_servers() -> Array:
	var servers: Array = [{"urls": [stun_server]}]
	if not turn_server.is_empty():
		(
			servers
			. append(
				{
					"urls": [turn_server],
					"username": turn_username,
					"credential": turn_credential,
				}
			)
		)
	return servers


func _create_rtc_peer(id: int) -> WebRTCPeerConnection:
	var peer := WebRTCPeerConnection.new()
	peer.initialize({"iceServers": _get_ice_servers()})
	peer.session_description_created.connect(_on_session_description.bind(id))
	peer.ice_candidate_created.connect(_on_ice_candidate.bind(id))
	_rtc_mp.add_peer(peer, id)
	# Lower ID initiates the offer
	if id < _rtc_mp.get_unique_id():
		peer.create_offer()
	return peer


func _on_id_received(id: int, _use_mesh: bool) -> void:
	print("WebRTC: signaling assigned ID %d" % id)
	if id == 1:
		_rtc_mp.create_server()
	else:
		_rtc_mp.create_client(id)
	_peer_ready = true


func _on_peer_connected(id: int) -> void:
	print("WebRTC: peer %d connected to signaling, creating RTC peer" % id)
	_create_rtc_peer(id)


func _on_peer_disconnected(id: int) -> void:
	print("WebRTC: peer %d disconnected" % id)
	if _rtc_mp.has_peer(id):
		_rtc_mp.remove_peer(id)


func _on_offer_received(id: int, offer: String) -> void:
	if _rtc_mp.has_peer(id):
		_rtc_mp.get_peer(id).connection.set_remote_description("offer", offer)


func _on_answer_received(id: int, answer: String) -> void:
	if _rtc_mp.has_peer(id):
		_rtc_mp.get_peer(id).connection.set_remote_description("answer", answer)


func _on_candidate_received(id: int, mid: String, index: int, sdp: String) -> void:
	if _rtc_mp.has_peer(id):
		_rtc_mp.get_peer(id).connection.add_ice_candidate(mid, index, sdp)


func _on_session_description(type: String, data: String, id: int) -> void:
	if not _rtc_mp.has_peer(id):
		return
	_rtc_mp.get_peer(id).connection.set_local_description(type, data)
	if type == "offer":
		_send_msg(Message.OFFER, id, data)
	else:
		_send_msg(Message.ANSWER, id, data)


func _on_ice_candidate(mid: String, index: int, sdp: String, id: int) -> void:
	_send_msg(Message.CANDIDATE, id, "\n%s\n%d\n%s" % [mid, index, sdp])


#endregion

#region IP detection (same as multiplayer_ipport.gd)


func _get_public_ip_addr() -> String:
	if OS.is_debug_build():
		return _get_private_ip_addr()

	var http := AwaitableHTTPRequest.new()
	add_child(http)

	var resp := await http.async_request("https://api.ipify.org")
	if resp.success() and resp.status_ok():
		http.queue_free()
		return resp.body_as_string()

	resp = await http.async_request("https://api6.ipify.org")
	http.queue_free()

	if resp.success() and resp.status_ok():
		return resp.body_as_string()

	printerr("Failed to fetch public IP address")
	return ""


func _get_private_ip_addr() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("10.") or ip.begins_with("172.16.") or ip.begins_with("192.168."):
			return ip
	return "0.0.0.0"


#endregion

#region Cleanup


func _cleanup():
	_ws.close()
	_rtc_mp.close()
	_lobby_code = ""
	_peer_ready = false
	_ws_old_state = WebSocketPeer.STATE_CLOSED
	_server_ip = ""

#endregion
