@tool
class_name MultiplayerManager extends BaseManager

signal player_connected(id: int, all_players: Dictionary)
signal player_disconnected(id: int)
signal server_disconnected
signal game_id_set(conn_addr: String)
signal client_connection_failed(reason: String)
signal client_connection_succeeded(peer_id: int)
signal lobby_players_updated(players: Dictionary)

enum ConnectionMode { NORAY, IP_PORT }

@export var menu_manager: MenuManager
@export var settings_manager: SettingsManager
@export var level_manager: LevelManager
@export var connection_mode: ConnectionMode = ConnectionMode.NORAY
@export var noray_handler: MultiplayerNoray
@export var ipport_handler: MultiplayerIPPort

## Maps peer ID (int) → PlayerDefinition
var lobby_players: Dictionary[int, PlayerDefinition] = {}
## either ip addr or noray oid
var conn_addr: String:
	set(val):
		conn_addr = val
		game_id_set.emit(val)


#region Public API
## Starts the ENet server and listens for connections.
func start_server():
	var handler = _get_handler()
	var peer: ENetMultiplayerPeer = await handler.start_server()
	handler.connection_failed.connect(_on_handler_connection_failed)
	conn_addr = handler.get_addr()

	if peer == null:
		printerr("failed to create server")
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
	lobby_players.clear()


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
	NetworkTime.stop()
	multiplayer.multiplayer_peer = null
	conn_addr = ""
	lobby_players.clear()


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


## Client calls this to send their PlayerDefinition to server; server updates dict and broadcasts
@rpc("any_peer", "call_local", "reliable")
func update_player_metadata(peer_id: int, player_def_dict: Dictionary):
	if !multiplayer.is_server():
		return

	var player_def = PlayerDefinition.new()
	player_def.from_dict(player_def_dict)
	lobby_players[peer_id] = player_def
	_sync_lobby_players.rpc(_lobby_players_to_dict())


#endregion

## Server broadcasts full lobby_players dict to all clients
@rpc("call_local", "reliable")
func _sync_lobby_players(players_dict: Dictionary):
	lobby_players.clear()
	for peer_id_str in players_dict:
		var peer_id = int(peer_id_str)
		var player_def = PlayerDefinition.new()
		player_def.from_dict(players_dict[peer_id_str])
		lobby_players[peer_id] = player_def
	lobby_players_updated.emit(lobby_players)


## return MultiplayerNoray or MultiplayerIPPort depending on connection_mode
func _get_handler():
	if connection_mode == ConnectionMode.NORAY:
		return noray_handler
	return ipport_handler


func _lobby_players_to_dict() -> Dictionary:
	var result = {}
	for peer_id in lobby_players:
		result[peer_id] = lobby_players[peer_id].to_dict()
	return result


#region signal handlers
func _on_server_disconnected():
	print("Disconnected from server")
	disconnect_client()
	server_disconnected.emit()


func _on_peer_connected(id: int):
	print("Player %s connected" % id)
	lobby_players[id] = PlayerDefinition.new()
	player_connected.emit(id, lobby_players)


func _on_peer_disconnected(id: int):
	print("Player %s disconnected" % id)
	player_disconnected.emit(id)

	lobby_players.erase(id)
	_sync_lobby_players.rpc(_lobby_players_to_dict())


func _on_handler_connection_failed(reason: String):
	client_connection_failed.emit(reason)


func _on_handler_connection_succeeded(peer_id: int):
	# Wait for ENet to actually connect before emitting
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		multiplayer.connected_to_server.connect(_on_enet_connected.bind(peer_id), CONNECT_ONE_SHOT)
	else:
		_on_enet_connected(peer_id)


func _on_enet_connected(peer_id: int):
	client_connection_succeeded.emit(peer_id)


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

	return issues
