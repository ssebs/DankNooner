@tool
class_name ConnectionManager extends BaseManager

signal player_connected(id: int)
signal player_disconnected(id: int)
signal server_disconnected
signal game_id_set(conn_addr: String)
signal client_connection_failed(reason: String)
signal client_connection_succeeded(peer_id: int)
signal connection_reset

enum ConnectionMode { NORAY, IP_PORT, WEBRTC }

@export var menu_manager: MenuManager
@export var settings_manager: SettingsManager
@export var level_manager: LevelManager
@export var connection_mode: ConnectionMode = ConnectionMode.WEBRTC
@export var noray_handler: MultiplayerNoray
@export var ipport_handler: MultiplayerIPPort
@export var webrtc_handler: MultiplayerWebRTC

## either ip addr or noray oid
var conn_addr: String:
	set(val):
		conn_addr = val
		game_id_set.emit(val)

var _enet_connected_callable: Callable


#region Public API
## Starts the ENet server and listens for connections.
func start_server():
	var handler = _get_handler()
	var peer: MultiplayerPeer = await handler.start_server()
	handler.connection_failed.connect(_on_handler_connection_failed)
	conn_addr = handler.get_addr()

	if peer == null:
		DebugUtils.DebugErrMsg("failed to create server")
		return

	multiplayer.multiplayer_peer = peer

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	_on_peer_connected(1)
	# emit signal as if the server connected as a client
	client_connection_succeeded.emit(1)


## Stops the running server & disconnects signals
func stop_server():
	var handler = _get_handler()
	if handler.connection_failed.is_connected(_on_handler_connection_failed):
		handler.connection_failed.disconnect(_on_handler_connection_failed)
	handler.stop_server()

	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)

	NetworkTime.stop()
	multiplayer.multiplayer_peer = null
	conn_addr = ""
	connection_reset.emit()


## Connects to a server at the given address. Returns OK on success, or an error code on failure.
## Address is Noray OID or IP depending on connection_mode.
func connect_client(address: String) -> Error:
	var handler = _get_handler()
	handler.connection_failed.connect(_on_handler_connection_failed)
	handler.connection_succeeded.connect(_on_handler_connection_succeeded)
	var err: Error = await handler.connect_client(address)
	if err != OK:
		if handler.connection_failed.is_connected(_on_handler_connection_failed):
			handler.connection_failed.disconnect(_on_handler_connection_failed)
		if handler.connection_succeeded.is_connected(_on_handler_connection_succeeded):
			handler.connection_succeeded.disconnect(_on_handler_connection_succeeded)
		return err
	conn_addr = address

	multiplayer.server_disconnected.connect(_on_server_disconnected)
	return OK


## Disconnects from server
func disconnect_client():
	var handler = _get_handler()
	if handler.connection_failed.is_connected(_on_handler_connection_failed):
		handler.connection_failed.disconnect(_on_handler_connection_failed)
	if handler.connection_succeeded.is_connected(_on_handler_connection_succeeded):
		handler.connection_succeeded.disconnect(_on_handler_connection_succeeded)
	handler.disconnect_client()

	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)
	_cleanup_enet_connected_signal()
	NetworkTime.stop()
	multiplayer.multiplayer_peer = null
	conn_addr = ""
	connection_reset.emit()


func disconnect_sp_or_mp():
	if multiplayer.multiplayer_peer == null:
		# Peer not set yet, but we may have pending handler signals to clean up
		_get_handler().stop_server()
		_get_handler().disconnect_client()
		return

	if multiplayer.is_server():
		stop_server()
	else:
		disconnect_client()


#endregion


## return MultiplayerNoray, MultiplayerIPPort, or MultiplayerWebRTC depending on connection_mode
func _get_handler():
	match connection_mode:
		ConnectionMode.NORAY:
			return noray_handler
		ConnectionMode.IP_PORT:
			return ipport_handler
		ConnectionMode.WEBRTC:
			return webrtc_handler
	return ipport_handler


#region signal handlers
func _on_server_disconnected():
	DebugUtils.DebugMsg("Disconnected from server")
	disconnect_client()
	server_disconnected.emit()


func _on_peer_connected(id: int):
	DebugUtils.DebugMsg("Player %s connected" % id)
	player_connected.emit(id)


func _on_peer_disconnected(id: int):
	DebugUtils.DebugMsg("Player %s disconnected" % id)
	player_disconnected.emit(id)


func _on_handler_connection_failed(reason: String):
	_cleanup_enet_connected_signal()
	client_connection_failed.emit(reason)


func _on_handler_connection_succeeded(peer_id: int):
	# Wait for ENet to actually connect before emitting
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		_cleanup_enet_connected_signal()
		_enet_connected_callable = _on_enet_connected.bind(peer_id)
		multiplayer.connected_to_server.connect(_enet_connected_callable, CONNECT_ONE_SHOT)
	else:
		_on_enet_connected(peer_id)


func _on_enet_connected(peer_id: int):
	_enet_connected_callable = Callable()
	client_connection_succeeded.emit(peer_id)


func _cleanup_enet_connected_signal():
	if (
		_enet_connected_callable.is_valid()
		and multiplayer.connected_to_server.is_connected(_enet_connected_callable)
	):
		multiplayer.connected_to_server.disconnect(_enet_connected_callable)
	_enet_connected_callable = Callable()


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if menu_manager == null:
		issues.append("menu_manager must not be empty")
	if level_manager == null:
		issues.append("level_manager must not be empty")
	if settings_manager == null:
		issues.append("settings_manager must not be empty")
	if noray_handler == null:
		issues.append("noray_handler must not be empty")
	if ipport_handler == null:
		issues.append("ipport_handler must not be empty")
	if webrtc_handler == null:
		issues.append("webrtc_handler must not be empty")

	return issues
