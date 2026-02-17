@tool
class_name LevelManager extends BaseManager

enum LevelName {
	LEVEL_SELECT_LABEL,  # not a level
	BG_GRAY_LEVEL,
	# MAIN_MENU_LEVEL,
	TEST_LEVEL_01,
}

@export var spawn_node: Node3D
@export var menu_manager: MenuManager
@export var multiplayer_manager: MultiplayerManager
@export var input_state_manager: InputStateManager

## PackedScene of type LevelDefinition
var possible_levels: Dictionary[LevelName, PackedScene] = {
	LevelName.LEVEL_SELECT_LABEL: null,
	LevelName.BG_GRAY_LEVEL: preload("res://levels/menu_levels/bg_gray/bg_gray_level.tscn"),
	LevelName.TEST_LEVEL_01: preload("res://levels/test_levels/test_01/test_01_level.tscn")
}
## LevelName enum => localization.csv's key name
var level_name_map: Dictionary[LevelName, String] = {
	LevelName.LEVEL_SELECT_LABEL: "LEVEL_SELECT_LABEL",
	LevelName.BG_GRAY_LEVEL: "BgGrayLevel",
	LevelName.TEST_LEVEL_01: "LEVEL_TEST_1_LABEL",
}
var levels_names_in_level_select: Array[String] = [
	"LEVEL_SELECT_LABEL",
	"LEVEL_TEST_1_LABEL",
]

var current_level_name: LevelName = LevelName.LEVEL_SELECT_LABEL
var current_level: LevelDefinition


func _ready():
	if Engine.is_editor_hint():
		return
	Console.add_command("dbg_gym", spawn_gym_test_level)


## Despawns any existing levels, then spawns level_name
## NOTE - also hides menus, and sets current_input_state
func spawn_level(level_name: LevelName, input_state: InputStateManager.InputState):
	if !possible_levels.has(level_name):
		printerr("Could not find LevelName.%s in possible_levels" % level_name)
		return

	despawn_level()

	var spawned_level = possible_levels[level_name].instantiate() as LevelDefinition
	spawned_level.name = level_name_map.get(level_name)
	spawned_level.level_manager = self
	spawn_node.add_child(spawned_level)
	current_level = spawned_level
	current_level_name = level_name

	input_state_manager.current_input_state = input_state
	if input_state == InputStateManager.InputState.IN_GAME:
		menu_manager.hide_all_menus()


func despawn_level():
	for child in spawn_node.get_children():
		child.queue_free()


@rpc("any_peer", "call_local", "reliable")
func respawn_player(player_peer_id: int):
	if !multiplayer.is_server():
		return

	var player_node := get_player_by_peer_id(player_peer_id)

	player_node.rb_do_respawn = true


func spawn_player(id: int):
	if !multiplayer.is_server():
		return

	var uname = multiplayer_manager.lobby_players[id]
	print("Spawning Player: %s - %s" % [id, uname])

	var player_to_add = multiplayer_manager.player_scene.instantiate() as PlayerEntity
	player_to_add.name = str(id)

	current_level.player_spawn_pos.add_child(player_to_add, true)
	player_to_add.set_username_label(uname)


func despawn_player(id: int):
	if !current_level.player_spawn_pos.has_node(str(id)):
		return

	current_level.player_spawn_pos.get_node(str(id)).queue_free()


#region specific level function calls
## Spawn the menu level
func spawn_menu_level():
	spawn_level(LevelName.BG_GRAY_LEVEL, InputStateManager.InputState.IN_MENU)


## for quick debugging
func spawn_gym_test_level():
	spawn_level(LevelName.TEST_LEVEL_01, InputStateManager.InputState.IN_GAME)


#endregion


#region helpers
func get_levels_as_option_items() -> Dictionary[String, int]:
	var options: Dictionary[String, int] = {}
	for lvl_name in levels_names_in_level_select:
		options[lvl_name] = level_name_map.find_key(lvl_name)
	return options


func get_player_by_peer_id(player_peer_id: int) -> PlayerEntity:
	var player_node: PlayerEntity
	for child in current_level.player_spawn_pos.get_children():
		if child is PlayerEntity:
			if child.name == str(player_peer_id):
				player_node = child
				break
	return player_node


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if spawn_node == null:
		issues.append("spawn_node must not be empty")
	if multiplayer_manager == null:
		issues.append("multiplayer_manager must not be empty")
	if menu_manager == null:
		issues.append("menu_manager must not be empty")
	if input_state_manager == null:
		issues.append("input_state_manager must not be empty")

	return issues
