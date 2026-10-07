@tool
class_name LevelManager extends BaseManager

enum LevelName {
	LEVEL_SELECT_LABEL,  # not a level
	BG_GRAY_LEVEL,
	# MAIN_MENU_LEVEL,
	TEST_LEVEL_01,
	TEST_CITY_01,
	RACETRACK_01,
	STUNTTRACK_01,
	STUNTTRACK_02,
	GARAGE_LEVEL,
	TRICK_DEMO_LEVEL,
}

@export var spawn_node: Node3D
@export var menu_manager: MenuManager
@export var input_state_manager: InputStateManager
@export var audio_manager: AudioManager
@export var hud_manager: HUDManager
@export var settings_manager: SettingsManager

const GAMMA_LUT_SIZE := 256

## PackedScene of type LevelDefinition
var possible_levels: Dictionary[LevelName, PackedScene] = {
	LevelName.LEVEL_SELECT_LABEL: null,
	LevelName.BG_GRAY_LEVEL: load("res://levels/menu_levels/bg_gray/bg_gray_level.tscn"),
	LevelName.TEST_LEVEL_01: load("res://levels/test_levels/test_01/test_01_level.tscn"),
	LevelName.TEST_CITY_01: load("res://levels/test_levels/test_city_01/test_city_01.tscn"),
	LevelName.RACETRACK_01:
	load("res://levels/racetracks/racetrack_level_01/racetrack_level_01.tscn"),
	LevelName.STUNTTRACK_01: load("res://levels/racetracks/stunt_track_01/stunt_track_01.tscn"),
	LevelName.STUNTTRACK_02: load("res://levels/racetracks/stunt_track_02/stunt_race_02.tscn"),
	LevelName.GARAGE_LEVEL: load("res://levels/menu_levels/garage/garage_level.tscn"),
	LevelName.TRICK_DEMO_LEVEL: load("res://levels/menu_levels/trick_demo/trick_demo_level.tscn"),
}
## LevelName enum => localization.csv's key name
var level_name_map: Dictionary[LevelName, String] = {
	LevelName.LEVEL_SELECT_LABEL: "LEVEL_SELECT_LABEL",
	LevelName.BG_GRAY_LEVEL: "BgGrayLevel",
	LevelName.TEST_LEVEL_01: "LEVEL_TEST_1_LABEL",
	LevelName.TEST_CITY_01: "LEVEL_TEST_CITY_01",
	LevelName.RACETRACK_01: "LEVEL_RACETRACK_01",
	LevelName.STUNTTRACK_01: "LEVEL_STUNTTRACK_01",
	LevelName.STUNTTRACK_02: "LEVEL_STUNTTRACK_02",
	LevelName.GARAGE_LEVEL: "GarageLevel",
	LevelName.TRICK_DEMO_LEVEL: "TrickDemoLevel",
}

# ___ UI ORDER ___ #
## There are in order for the option btn ##
var levels_names_in_level_select: Array[String] = [
	"LEVEL_SELECT_LABEL", # leave as first option
	"LEVEL_STUNTTRACK_01",
	"LEVEL_STUNTTRACK_02",
	"LEVEL_RACETRACK_01",
	"LEVEL_TEST_CITY_01",
	"LEVEL_TEST_1_LABEL",
]
## LevelName enum => image used in level preview
var level_img_map: Dictionary[LevelName,Texture] = {
	LevelName.TEST_LEVEL_01: load("res://resources/img/level_previews/TEST_LEVEL_01.jpg"),
	LevelName.TEST_CITY_01: load("res://resources/img/level_previews/TEST_CITY_01.jpg"),
	LevelName.RACETRACK_01: load("res://resources/img/level_previews/RACETRACK_01.jpg"),
	LevelName.STUNTTRACK_01: load("res://resources/img/level_previews/STUNT_CITY.jpg"),
}

var current_level_name: LevelName = LevelName.LEVEL_SELECT_LABEL
var current_level: LevelDefinition


func _ready():
	if Engine.is_editor_hint():
		return
	# Console.add_command("dbg_gym", spawn_gym_test_level) # broken
	settings_manager.all_settings_changed.connect(func(_s): _apply_gamma())


#region public api


## Despawns any existing levels, then spawns level_name
## NOTE - also hides menus, and sets current_input_state
func spawn_level(level_name: LevelName, input_state: InputStateManager.InputState):
	if !possible_levels.has(level_name):
		DebugUtils.DebugErrMsg("Could not find LevelName.%s in possible_levels" % level_name)
		return

	# Reset the HUD before despawn so RidingHUDState stops polling the player being freed.
	# Re-enters on the next player spawn (needed for IN_GAME->IN_GAME map switches too).
	hud_manager.go_to_null_hud()
	despawn_level()

	var spawned_level = possible_levels[level_name].instantiate() as LevelDefinition
	spawned_level.name = level_name_map.get(level_name)
	spawned_level.level_name = level_name
	spawned_level.level_manager = self
	spawn_node.add_child(spawned_level)
	current_level = spawned_level
	current_level_name = level_name
	_apply_gamma()

	input_state_manager.current_input_state = input_state
	if input_state == InputStateManager.InputState.IN_GAME:
		menu_manager.switch_to_pause_menu()
		menu_manager.hide_all_menus()
		if audio_manager:
			audio_manager.play_maximize()


func despawn_level():
	for child in spawn_node.get_children():
		child.queue_free()


## Spawn the menu level
func spawn_menu_level():
	spawn_level(LevelName.BG_GRAY_LEVEL, InputStateManager.InputState.IN_MENU)


## Spawn the menu garage level, viewed through its bay's camera. Returns the bay.
func spawn_garage_level() -> GarageActivity:
	spawn_level(LevelName.GARAGE_LEVEL, InputStateManager.InputState.IN_MENU)
	var bay: GarageActivity = current_level.find_children("*", "GarageActivity", true, false)[0]
	bay.camera.make_current()
	return bay


func get_levels_as_option_items() -> Dictionary[String, int]:
	var options: Dictionary[String, int] = {}
	for lvl_name in levels_names_in_level_select:
		options[lvl_name] = level_name_map.find_key(lvl_name)
	return options


#endregion


## Gamma setting 0..1 maps to gamma 0.5..2.0 (0.5 is neutral), applied post-tonemap as a
## color-correction LUT. Needs adjustment_enabled on the level's Environment (off on web).
func _apply_gamma():
	# Settings load deferred and levels spawn later; whichever runs second applies it
	if current_level == null or settings_manager.current_settings.is_empty():
		return
	var gamma := pow(2.0, (settings_manager.current_settings["gamma"] - 0.5) * 2.0)
	# Half-float so steep curves don't band in dark gradients
	var lut := Image.create_empty(GAMMA_LUT_SIZE, 1, false, Image.FORMAT_RGBH)
	for x in GAMMA_LUT_SIZE:
		var v := pow(x / float(GAMMA_LUT_SIZE - 1), 1.0 / gamma)
		lut.set_pixel(x, 0, Color(v, v, v))
	var lut_tex := ImageTexture.create_from_image(lut)
	for world_env: WorldEnvironment in current_level.find_children(
		"*", "WorldEnvironment", true, false
	):
		world_env.environment.adjustment_color_correction = lut_tex


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if spawn_node == null:
		issues.append("spawn_node must not be empty")
	if menu_manager == null:
		issues.append("menu_manager must not be empty")
	if input_state_manager == null:
		issues.append("input_state_manager must not be empty")
	if audio_manager == null:
		issues.append("audio_manager must not be empty")
	if hud_manager == null:
		issues.append("hud_manager must not be empty")
	if settings_manager == null:
		issues.append("settings_manager must not be empty")

	return issues
