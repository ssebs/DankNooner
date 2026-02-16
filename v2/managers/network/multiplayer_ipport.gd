class_name MultiplayerIPPort extends Node

signal connection_failed(reason: String)
signal connection_succeeded

var ip_addr: String = "0.0.0.0"


## Creates and returns an ENet server peer on UtilsConstants.PORT.
## Emits server_started with the public IP after peer is created.
func start_server() -> ENetMultiplayerPeer:
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(UtilsConstants.PORT)
	if err != OK:
		printerr("failed to create server on port %d" % UtilsConstants.PORT)
		return null

	# Fetch public IP in background and emit when ready
	ip_addr = await _get_public_ip_addr()
	return peer


## No-op for IP/Port mode (nothing to clean up).
func stop_server():
	pass


## Connects directly to the given IP address via ENet. Returns OK on success.
func connect_client(ip: String) -> Error:
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip, UtilsConstants.PORT)

	if err != OK:
		connection_failed.emit("Failed to connect to %s:%d" % [ip, UtilsConstants.PORT])
		return err

	multiplayer.multiplayer_peer = peer
	connection_succeeded.emit()
	return OK


## No-op for IP/Port mode (nothing to clean up).
func disconnect_client():
	pass


func get_addr():
	return ip_addr


## Fetches public IP address. Returns private IP in debug builds.
func _get_public_ip_addr() -> String:
	if OS.is_debug_build():
		return _get_private_ip_addr()

	var http := AwaitableHTTPRequest.new()
	add_child(http)

	# Try IPv4 first
	var resp := await http.async_request("https://api.ipify.org")
	if resp.success() and resp.status_ok():
		http.queue_free()
		return resp.body_as_string()

	# Fallback to IPv6
	resp = await http.async_request("https://api6.ipify.org")
	http.queue_free()

	if resp.success() and resp.status_ok():
		return resp.body_as_string()

	printerr("Failed to fetch public IP address")
	return ""


# NOTE - this doesn't always get the correct IP addr
func _get_private_ip_addr() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("10.") or ip.begins_with("172.16.") or ip.begins_with("192.168."):
			return ip
	return "0.0.0.0"
