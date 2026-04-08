@tool
class_name SpawnManager extends BaseManager

signal player_spawned(player: PlayerEntity)

@export var lobby_manager: LobbyManager
@export var level_manager: LevelManager
@export var audio_manager: AudioManager
@export var settings_manager: SettingsManager


func _ready():
	if Engine.is_editor_hint():
		return
	lobby_manager.lobby_players_updated.connect(_on_lobby_players_updated)


## Spawn all players from lobby_players dict (server only)
func spawn_all_players():
	if !multiplayer.is_server():
		return

	for peer_id in lobby_manager.lobby_players:
		var player_def: PlayerDefinition = lobby_manager.lobby_players[peer_id]
		rpc_spawn_player.rpc(peer_id, player_def.to_dict())


## Server broadcasts to all peers to spawn a player
@rpc("call_local", "reliable")
func rpc_spawn_player(peer_id: int, player_def_dict: Dictionary):
	add_player_locally(peer_id, player_def_dict)


## Server broadcasts to all peers to despawn a player
@rpc("call_local", "reliable")
func rpc_despawn_player(peer_id: int):
	remove_player_locally(peer_id)


## Update all spawned players' skins from lobby data.
func _on_lobby_players_updated(players: Dictionary):
	if level_manager.current_level.no_player_spawn_needed:
		return

	for peer_id in players:
		# Player may not be spawned yet during late-join sync — skip is intentional
		var player := _get_player_by_peer_id(peer_id)
		if player == null:
			continue
		player.update_skins(players[peer_id].bike_skin, players[peer_id].character_skin)


## Set player's rb_do_respawn to true
@rpc("any_peer", "call_local", "reliable")
func respawn_player(player_peer_id: int):
	if !multiplayer.is_server():
		return

	var player_node := _get_player_by_peer_id(player_peer_id)

	player_node.rb_do_respawn = true


## Instantiate and add player node locally (no authority check)
func add_player_locally(peer_id: int, player_def_dict: Dictionary):
	var player_def = PlayerDefinition.new()
	player_def.from_dict(player_def_dict)

	DebugUtils.DebugMsg("Adding player locally: %s - %s" % [peer_id, player_def.username])

	var player_to_add = (
		level_manager.current_level.player_entity_scene.instantiate() as PlayerEntity
	)
	player_to_add.name = str(peer_id)
	player_to_add.audio_manager = audio_manager  # HACK
	player_to_add.settings_manager = settings_manager  # HACK
	player_to_add.bike_definition = player_def.bike_skin
	player_to_add.character_definition = player_def.character_skin

	level_manager.current_level.player_spawn_pos.add_child(player_to_add, true)
	player_to_add.username = player_def.username
	player_spawned.emit(player_to_add)


## Remove player node locally (no authority check)
func remove_player_locally(peer_id: int):
	if !level_manager.current_level.player_spawn_pos.has_node(str(peer_id)):
		return

	level_manager.current_level.player_spawn_pos.get_node(str(peer_id)).queue_free()


## Get player from multiplayer peer id found in level_manager.current_level
func _get_player_by_peer_id(player_peer_id: int) -> PlayerEntity:
	var player_node: PlayerEntity
	for child in level_manager.current_level.player_spawn_pos.get_children():
		if child is PlayerEntity:
			if child.name == str(player_peer_id):
				player_node = child
				break
	return player_node


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if audio_manager == null:
		issues.append("audio_manager must not be empty")
	if lobby_manager == null:
		issues.append("lobby_manager must not be empty")
	if level_manager == null:
		issues.append("level_manager must not be empty")
	if settings_manager == null:
		issues.append("settings_manager must not be empty")

	return issues
