class_name MultiplayerIPPort extends Node


signal server_started(public_ip: String)

var _http: HTTPRequest
var _trying_ipv6: bool = false


## Creates and returns an ENet server peer on UtilsConstants.PORT.
## Emits server_started with the public IP after peer is created.
func start_server() -> ENetMultiplayerPeer:
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(UtilsConstants.PORT)
	if err != OK:
		printerr("failed to create server on port %d" % UtilsConstants.PORT)
		return null

	# Fetch public IP in background and emit when ready
	get_public_ip_addr()
	return peer


## No-op for IP/Port mode (nothing to clean up).
func stop_server():
	pass


## Connects directly to the given IP address via ENet. Returns OK on success.
func connect_client(ip: String) -> Error:
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip, UtilsConstants.PORT)

	if err != OK:
		return err

	multiplayer.multiplayer_peer = peer
	return OK


## No-op for IP/Port mode (nothing to clean up).
func disconnect_client():
	pass


func get_public_ip_addr():
	if OS.is_debug_build():
		server_started.emit(get_private_ip_addr())
		return
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_ip_request_completed)
	_trying_ipv6 = false
	_http.request("https://api.ipify.org")

func get_private_ip_addr():
	var addresses = []
	for ip in IP.get_local_addresses():
		if ip.begins_with("10.") or ip.begins_with("172.16.") or ip.begins_with("192.168."):
			addresses.push_back(ip)
	return addresses[0]


func _on_ip_request_completed(
		_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
):
	if response_code == 200:
		var ip = body.get_string_from_utf8()
		_cleanup_http()
		server_started.emit(ip)
		return

	# Try IPv6 fallback if we haven't already
	if not _trying_ipv6:
		_trying_ipv6 = true
		_http.request("https://api6.ipify.org")
		return

	# Both failed
	_cleanup_http()
	server_started.emit("")


func _cleanup_http():
	if _http:
		_http.request_completed.disconnect(_on_ip_request_completed)
		_http.queue_free()
		_http = null
