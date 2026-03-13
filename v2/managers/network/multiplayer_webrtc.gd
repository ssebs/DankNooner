class_name MultiplayerWebRTC extends Node

## WebRTC multiplayer handler using a remote signaling server.
## Both host and client connect to the signaling server via WebSocket.
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

## URL of the remote signaling server
@export var signaling_url: String = "wss://signal.ssebs.com"

## STUN/TURN server URL for ICE negotiation
@export var stun_server: String = "stun:stun.ssebs.com:3478"

## Optional TURN server URL (for relay fallback behind symmetric NAT)
@export var turn_server: String = "turn:stun.ssebs.com:3478"
@export var turn_username: String = "danknooner"
@export var turn_credential: String = "passTEST"

const SETUP_TIMEOUT_MS = 10000

var _lobby_code: String = ""
var _ws: WebSocketPeer
var _ws_old_state := WebSocketPeer.STATE_CLOSED
var _rtc_mp: WebRTCMultiplayerPeer
var _is_server: bool = false
var _peer_ready: bool = false
var _setup_in_progress: bool = false

#region Public API (handler interface)


## Connects to the remote signaling server as host and creates a lobby.
## Returns the WebRTCMultiplayerPeer once ready.
func start_server() -> MultiplayerPeer:
	_is_server = true
	_peer_ready = false
	_setup_in_progress = true
	_lobby_code = ""
	_ws = WebSocketPeer.new()
	_rtc_mp = WebRTCMultiplayerPeer.new()
	_ws_old_state = WebSocketPeer.STATE_CLOSED

	_ws.connect_to_url(signaling_url)

	var start_time := Time.get_ticks_msec()
	while not _peer_ready:
		if Time.get_ticks_msec() - start_time > SETUP_TIMEOUT_MS:
			printerr("WebRTC: server setup timed out")
			_setup_in_progress = false
			return null
		await get_tree().process_frame
		_poll_ws()

	_setup_in_progress = false
	return _rtc_mp


func stop_server():
	_cleanup()


## Joins an existing lobby by code via the remote signaling server.
## Address format: lobby code only (e.g. "ABCxyz123")
func connect_client(address: String) -> Error:
	_is_server = false
	_peer_ready = false
	_setup_in_progress = true
	_lobby_code = address.strip_edges()
	_ws = WebSocketPeer.new()
	_rtc_mp = WebRTCMultiplayerPeer.new()
	_ws_old_state = WebSocketPeer.STATE_CLOSED

	if _lobby_code.is_empty():
		connection_failed.emit("Lobby code is required")
		_setup_in_progress = false
		return ERR_INVALID_PARAMETER

	_ws.connect_to_url(signaling_url)

	var start_time := Time.get_ticks_msec()
	while not _peer_ready:
		if Time.get_ticks_msec() - start_time > SETUP_TIMEOUT_MS:
			printerr("WebRTC: client setup timed out")
			connection_failed.emit("Connection timed out")
			_cleanup()
			_setup_in_progress = false
			return ERR_TIMEOUT
		await get_tree().process_frame
		_poll_ws()

	_setup_in_progress = false
	multiplayer.multiplayer_peer = _rtc_mp
	connection_succeeded.emit(_rtc_mp.get_unique_id())
	return OK


func disconnect_client():
	_cleanup()


## Returns the lobby code clients need to join.
func get_addr() -> String:
	return _lobby_code


#endregion

#region WebSocket polling & signaling client


func _process(_delta: float) -> void:
	# During setup, the await loops handle polling — skip here to avoid double-processing
	if _setup_in_progress:
		return
	_poll_ws()


func _poll_ws() -> void:
	if _ws == null:
		return
	_ws.poll()
	var state := _ws.get_ready_state()

	# On first open, join/create lobby
	if state != _ws_old_state and state == WebSocketPeer.STATE_OPEN:
		# id=1 means client-server mode (not mesh); data="" creates, code joins
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
	_send_msg(Message.CANDIDATE, id, "%s\n%d\n%s" % [mid, index, sdp])


#endregion

#region Cleanup


func _cleanup():
	if _ws != null:
		_ws.close()
	if _rtc_mp != null:
		_rtc_mp.close()
	_lobby_code = ""
	_peer_ready = false
	_setup_in_progress = false
	_is_server = false
	_ws_old_state = WebSocketPeer.STATE_CLOSED

#endregion
