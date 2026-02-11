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


func get_levels_as_option_items() -> Dictionary[String, int]:
	var options: Dictionary[String, int] = {}
	for v in level_name_map.values():
		options[v] = level_name_map.find_key(v)
	return options


## Spawn the menu level
func spawn_menu_level():
	spawn_level(LevelName.BG_GRAY_LEVEL, InputStateManager.InputState.IN_MENU)


## for quick debugging
func spawn_gym_test_level():
	spawn_level(LevelName.TEST_LEVEL_01, InputStateManager.InputState.IN_GAME)

# ## Get a map of LevelName => LevelState for all children of this mgr
# func get_all_levels() -> Dictionary[String, LevelState]:
# 	return level_name_state_map

# func get_level_by_name(name_to_check: String) -> LevelState:
# 	return level_name_state_map.get(name_to_check)
