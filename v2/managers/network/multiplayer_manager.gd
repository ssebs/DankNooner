@tool
class_name MultiplayerManager extends BaseManager

signal player_connected(id: int, all_players: Array[int])
signal player_disconnected(id: int)
signal server_disconnected
signal game_id_set(noray_oid: String)

@export var menu_manager: MenuManager
@export var level_manager: LevelManager
@export var player_scene = preload("res://entities/player/player_entity.tscn")
# @export var noray_host: String = "home.ssebs.com"
@export var noray_host: String = "noray.casa.ssebs.com"
# @export var noray_host: String = "tomfol.io"

@export var force_relay_mode: bool = false

# const PORT: int = 42068
var lobby_players: Array[int] = []
var noray_oid: String:
	set(val):
		noray_oid = val
		game_id_set.emit(val)


#region Public API
## Starts the ENet server and listens for connections.
func start_server():
	Noray.on_connect_nat.connect(_handle_noray_client_connect)
	Noray.on_connect_relay.connect(_handle_noray_client_connect)

	await _register_with_noray()

	var err = OK
	var peer = ENetMultiplayerPeer.new()
	err = peer.create_server(Noray.local_port)
	if err != OK:
		printerr("failed to create server")
		return

	multiplayer.multiplayer_peer = peer

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	_on_peer_connected(1)


## Stops the running server & disconnects signals
func stop_server():
	Noray.on_connect_nat.disconnect(_handle_noray_client_connect)
	Noray.on_connect_relay.disconnect(_handle_noray_client_connect)

	multiplayer.peer_connected.disconnect(_on_peer_connected)
	multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)

	multiplayer.multiplayer_peer = null
	lobby_players.clear()


## Connects to a server at the given IP.
func connect_client(noray_host_oid: String):
	Noray.on_connect_nat.connect(_handle_noray_connect_nat)
	Noray.on_connect_relay.connect(_handle_noray_connect)

	await _register_with_noray()
	noray_oid = noray_host_oid

	var err = OK
	if force_relay_mode:
		err = Noray.connect_relay(noray_oid)
	else:
		err = Noray.connect_nat(noray_oid)
	if err != OK:
		printerr("failed to connect_nat")
		return
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


#region noray
func _register_with_noray():
	var err = OK
	err = await Noray.connect_to_host(noray_host, 8890)
	if err != OK:
		printerr("noray failed to connect to noray @ %s" % noray_host)
		return

	Noray.register_host()
	await Noray.on_pid
	noray_oid = Noray.oid

	err = await Noray.register_remote()
	if err != OK:
		printerr("noray failed to connect to register_remote")
		return


func _handle_noray_client_connect(address: String, port: int):
	var peer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	var err = await PacketHandshake.over_enet(peer.host, address, port)
	if err != OK:
		printerr("noray packed handshake failed")


func _handle_noray_connect_nat(address: String, port: int):
	var err = await _handle_noray_connect(address, port)
	if err != OK:
		printerr("NAT connection failed, trying relay")
		Noray.connect_relay(noray_oid)


func _handle_noray_connect(address: String, port: int) -> Error:
	var udp = PacketPeerUDP.new()
	udp.bind(Noray.local_port)
	udp.set_dest_address(address, port)

	var err = await PacketHandshake.over_packet_peer(udp)
	udp.close()

	if err != OK:
		return err

	# Connect to host
	var peer = ENetMultiplayerPeer.new()
	err = peer.create_client(address, port, 0, 0, 0, Noray.local_port)

	if err != OK:
		return err

	multiplayer.multiplayer_peer = peer
	return OK


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if menu_manager == null:
		issues.append("menu_manager must not be empty")
	if level_manager == null:
		issues.append("level_manager must not be empty")

	return issues
