@tool
class_name SpawnManager extends BaseManager

@export var multiplayer_manager: MultiplayerManager
@export var level_manager: LevelManager
@export var audio_manager: AudioManager

@rpc("any_peer", "call_local", "reliable")
func respawn_player(player_peer_id: int):
	if !multiplayer.is_server():
		return

	var player_node := get_player_by_peer_id(player_peer_id)

	player_node.rb_do_respawn = true


## Instantiate and add player node locally (no authority check)
## Called by GamemodeManager RPC on all peers
func add_player_locally(
	peer_id: int, username: String, bike_skin_path: String = "", character_skin_path: String = ""
):
	print("Adding player locally: %s - %s" % [peer_id, username])

	var player_to_add = (
		level_manager.current_level.player_entity_scene.instantiate() as PlayerEntity
	)
	player_to_add.name = str(peer_id)
	player_to_add.audio_manager = audio_manager  # HACK

	if bike_skin_path != "":
		var bike_res = ResourceLoader.load(bike_skin_path)
		if bike_res is BikeSkinDefinition:
			player_to_add.bike_definition = bike_res

	if character_skin_path != "":
		var char_res = ResourceLoader.load(character_skin_path)
		if char_res is CharacterSkinDefinition:
			player_to_add.character_definition = char_res

	level_manager.current_level.player_spawn_pos.add_child(player_to_add, true)
	player_to_add.username = username


func get_player_by_peer_id(player_peer_id: int) -> PlayerEntity:
	var player_node: PlayerEntity
	for child in level_manager.current_level.player_spawn_pos.get_children():
		if child is PlayerEntity:
			if child.name == str(player_peer_id):
				player_node = child
				break
	return player_node


## Remove player node locally (no authority check)
## Called by GamemodeManager RPC on all peers
func remove_player_locally(peer_id: int):
	if !level_manager.current_level.player_spawn_pos.has_node(str(peer_id)):
		return

	level_manager.current_level.player_spawn_pos.get_node(str(peer_id)).queue_free()


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if audio_manager == null:
		issues.append("audio_manager must not be empty")
	if multiplayer_manager == null:
		issues.append("multiplayer_manager must not be empty")
	if level_manager == null:
		issues.append("level_manager must not be empty")

	return issues
