@tool
class_name SpawnManager extends BaseManager

@export var multiplayer_manager: MultiplayerManager
@export var level_manager: LevelManager
@export var audio_manager: AudioManager

## Set player's rb_do_respawn to true
@rpc("any_peer", "call_local", "reliable")
func respawn_player(player_peer_id: int):
	if !multiplayer.is_server():
		return

	var player_node := _get_player_by_peer_id(player_peer_id)

	player_node.rb_do_respawn = true


## Instantiate and add player node locally (no authority check)
## Called by GamemodeManager RPC on all peers
func add_player_locally(peer_id: int, player_def_dict: Dictionary):
	var player_def = PlayerDefinition.new()
	player_def.from_dict(player_def_dict)

	print("Adding player locally: %s - %s" % [peer_id, player_def.username])

	var player_to_add = (
		level_manager.current_level.player_entity_scene.instantiate() as PlayerEntity
	)
	player_to_add.name = str(peer_id)
	player_to_add.audio_manager = audio_manager  # HACK
	player_to_add.bike_definition = player_def.bike_skin
	player_to_add.character_definition = player_def.character_skin

	level_manager.current_level.player_spawn_pos.add_child(player_to_add, true)
	player_to_add.username = player_def.username


## Remove player node locally (no authority check)
## Called by GamemodeManager RPC on all peers
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
	if multiplayer_manager == null:
		issues.append("multiplayer_manager must not be empty")
	if level_manager == null:
		issues.append("level_manager must not be empty")

	return issues
