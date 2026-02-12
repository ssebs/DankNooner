@tool
class_name MultiplayerManager extends BaseManager

signal player_connected(id: int, all_players: Array[int])
signal player_disconnected(id: int)
signal server_disconnected

@export var menu_manager: MenuManager
@export var level_manager: LevelManager
@export var player_scene = preload("res://entities/player/player_entity.tscn")

const PORT: int = 42068

var lobby_players: Array[int] = []


#region Public API
## Starts the ENet server and listens for connections.
func start_server():
	var peer = ENetMultiplayerPeer.new()
	peer.create_server(PORT)
	multiplayer.multiplayer_peer = peer

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	_on_peer_connected(1)


## Stops the running server & disconnects signals
func stop_server():
	multiplayer.peer_connected.disconnect(_on_peer_connected)
	multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)

	multiplayer.multiplayer_peer = null
	lobby_players.clear()


## Connects to a server at the given IP.
func connect_client(ip_addr: String = "127.0.0.1"):
	var peer = ENetMultiplayerPeer.new()
	peer.create_client(ip_addr, PORT)
	multiplayer.multiplayer_peer = peer
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## Disconnects from server
func disconnect_client():
	multiplayer.server_disconnected.disconnect(_on_server_disconnected)
	multiplayer.multiplayer_peer = null
	lobby_players.clear()


func disconnect_sp_or_mp():
	if multiplayer.multiplayer_peer != null:
		if multiplayer.is_server():
			stop_server()
		else:
			disconnect_client()


## Spawns players in lobby_players. Called when game starts.
func spawn_players():
	for p in lobby_players:
		_spawn_player(p)


#endregion


func _spawn_player(id: int):
	print("Spawning Player: %s" % id)

	var player_to_add = player_scene.instantiate() as PlayerEntity
	player_to_add.name = str(id)

	level_manager.current_level.player_spawn_pos.add_child(player_to_add, true)


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
	server_disconnected.emit()
	multiplayer.multiplayer_peer = null
	lobby_players.clear()


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if menu_manager == null:
		issues.append("menu_manager must not be empty")
	if level_manager == null:
		issues.append("level_manager must not be empty")

	return issues
