@tool
class_name LevelManager extends BaseManager

enum LevelName {
	LEVEL_SELECT_LABEL,  # not a level
	BG_GRAY_LEVEL,
	# MAIN_MENU_LEVEL,
	TEST_LEVEL_01,
	TEST_CITY_01,
}

@export var spawn_node: Node3D
@export var menu_manager: MenuManager
@export var input_state_manager: InputStateManager

## PackedScene of type LevelDefinition
var possible_levels: Dictionary[LevelName, PackedScene] = {
	LevelName.LEVEL_SELECT_LABEL: null,
	LevelName.BG_GRAY_LEVEL: load("res://levels/menu_levels/bg_gray/bg_gray_level.tscn"),
	LevelName.TEST_LEVEL_01: load("res://levels/test_levels/test_01/test_01_level.tscn"),
	LevelName.TEST_CITY_01: load("res://levels/test_levels/test_city_01/test_city_01.tscn"),
}
## LevelName enum => localization.csv's key name
var level_name_map: Dictionary[LevelName, String] = {
	LevelName.LEVEL_SELECT_LABEL: "LEVEL_SELECT_LABEL",
	LevelName.BG_GRAY_LEVEL: "BgGrayLevel",
	LevelName.TEST_LEVEL_01: "LEVEL_TEST_1_LABEL",
	LevelName.TEST_CITY_01: "LEVEL_TEST_CITY_01",
}
var levels_names_in_level_select: Array[String] = [
	"LEVEL_SELECT_LABEL",
	"LEVEL_TEST_1_LABEL",
	"LEVEL_TEST_CITY_01",
]
## LevelName enum => image used in level preview
var level_img_map: Dictionary[LevelName,Texture] = {
	LevelName.TEST_LEVEL_01: load("res://resources/img/level_previews/TEST_LEVEL_01.jpg"),
	LevelName.TEST_CITY_01: load("res://resources/img/level_previews/TEST_CITY_01.jpg"),
}

var current_level_name: LevelName = LevelName.LEVEL_SELECT_LABEL
var current_level: LevelDefinition


func _ready():
	if Engine.is_editor_hint():
		return
	# Console.add_command("dbg_gym", spawn_gym_test_level) # broken


#region public api


## Despawns any existing levels, then spawns level_name
## NOTE - also hides menus, and sets current_input_state
func spawn_level(level_name: LevelName, input_state: InputStateManager.InputState):
	if !possible_levels.has(level_name):
		printerr("Could not find LevelName.%s in possible_levels" % level_name)
		return

	despawn_level()

	var spawned_level = possible_levels[level_name].instantiate() as LevelDefinition
	spawned_level.name = level_name_map.get(level_name)
	spawned_level.level_name = level_name
	spawned_level.level_manager = self
	spawn_node.add_child(spawned_level)
	current_level = spawned_level
	current_level_name = level_name

	input_state_manager.current_input_state = input_state
	if input_state == InputStateManager.InputState.IN_GAME:
		menu_manager.switch_to_pause_menu()
		menu_manager.hide_all_menus()


func despawn_level():
	for child in spawn_node.get_children():
		child.queue_free()


## Spawn the menu level
func spawn_menu_level():
	spawn_level(LevelName.BG_GRAY_LEVEL, InputStateManager.InputState.IN_MENU)


func get_levels_as_option_items() -> Dictionary[String, int]:
	var options: Dictionary[String, int] = {}
	for lvl_name in levels_names_in_level_select:
		options[lvl_name] = level_name_map.find_key(lvl_name)
	return options


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if spawn_node == null:
		issues.append("spawn_node must not be empty")
	if menu_manager == null:
		issues.append("menu_manager must not be empty")
	if input_state_manager == null:
		issues.append("input_state_manager must not be empty")

	return issues
