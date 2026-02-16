@tool
class_name MultiplayerManager extends BaseManager

signal player_connected(id: int, all_players: Array[int])
signal player_disconnected(id: int)
signal server_disconnected
signal game_id_set(conn_addr: String)
signal client_connection_failed(reason: String)

enum ConnectionMode {NORAY, IP_PORT}

@export var menu_manager: MenuManager
@export var level_manager: LevelManager
@export var player_scene = preload("res://entities/player/player_entity.tscn")
@export var connection_mode: ConnectionMode = ConnectionMode.NORAY
@export var noray_handler: MultiplayerNoray
@export var ipport_handler: MultiplayerIPPort

var lobby_players: Array[int] = []
## either ip addr or noray oid
var conn_addr: String:
	set(val):
		conn_addr = val
		game_id_set.emit(val)


#region Public API
## Starts the ENet server and listens for connections.
func start_server():
	var peer: ENetMultiplayerPeer
	if connection_mode == ConnectionMode.NORAY:
		peer = await noray_handler.start_server()
		noray_handler.connection_failed.connect(_on_handler_connection_failed)
		conn_addr = noray_handler.get_oid()
	else:
		peer = await ipport_handler.start_server()
		conn_addr = ipport_handler.get_ip()

	if peer == null:
		printerr("failed to create server")
		return

	multiplayer.multiplayer_peer = peer

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


	_on_peer_connected(1)


## Stops the running server & disconnects signals
func stop_server():
	if connection_mode == ConnectionMode.NORAY:
		if noray_handler.connection_failed.is_connected(_on_handler_connection_failed):
			noray_handler.connection_failed.disconnect(_on_handler_connection_failed)
		noray_handler.stop_server()
	else:
		ipport_handler.stop_server()

	multiplayer.peer_connected.disconnect(_on_peer_connected)
	multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)

	multiplayer.multiplayer_peer = null
	conn_addr = ""
	lobby_players.clear()


## Connects to a server at the given address. Returns OK on success, or an error code on failure.
## Address is Noray OID or IP depending on connection_mode.
func connect_client(address: String) -> Error:
	var err: Error
	if connection_mode == ConnectionMode.NORAY:
		noray_handler.connection_failed.connect(_on_handler_connection_failed)
		err = await noray_handler.connect_client(address)
		if err != OK:
			if noray_handler.connection_failed.is_connected(_on_handler_connection_failed):
				noray_handler.connection_failed.disconnect(_on_handler_connection_failed)
			return err
		conn_addr = address
	else:
		err = ipport_handler.connect_client(address)
		if err != OK:
			client_connection_failed.emit("Failed to connect to %s:%d" % [address, UtilsConstants.PORT])
			return err
		conn_addr = address

	multiplayer.server_disconnected.connect(_on_server_disconnected)
	return OK


## Disconnects from server
func disconnect_client():
	if connection_mode == ConnectionMode.NORAY:
		if noray_handler.connection_failed.is_connected(_on_handler_connection_failed):
			noray_handler.connection_failed.disconnect(_on_handler_connection_failed)
		noray_handler.disconnect_client()
	else:
		ipport_handler.disconnect_client()

	multiplayer.server_disconnected.disconnect(_on_server_disconnected)
	multiplayer.multiplayer_peer = null
	conn_addr = ""
	lobby_players.clear()


func disconnect_sp_or_mp():
	if multiplayer.multiplayer_peer != null:
		if multiplayer.is_server():
			stop_server()
		else:
			disconnect_client()


#endregion


func _on_peer_connected(id: int):
	print("Player %s connected" % id)
	lobby_players.append(id)
	player_connected.emit(id, lobby_players)


func _on_peer_disconnected(id: int):
	print("Player %s disconnected" % id)
	player_disconnected.emit(id)

	lobby_players.erase(id)

	if level_manager.current_level.no_player_spawn_needed:
		return

	if !level_manager.current_level.player_spawn_pos.has_node(str(id)):
		return

	level_manager.current_level.player_spawn_pos.get_node(str(id)).queue_free()


func _on_server_disconnected():
	print("Disconnected from server")
	disconnect_client()
	server_disconnected.emit()


func _on_handler_connection_failed(reason: String):
	client_connection_failed.emit(reason)


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if menu_manager == null:
		issues.append("menu_manager must not be empty")
	if level_manager == null:
		issues.append("level_manager must not be empty")
	if noray_handler == null:
		issues.append("noray_handler must not be empty")
	if ipport_handler == null:
		issues.append("ipport_handler must not be empty")

	return issues
