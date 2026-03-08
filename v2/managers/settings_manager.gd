@tool
class_name SettingsManager extends BaseManager

signal all_settings_changed(current_settings: Dictionary)
signal setting_updated(key: String, value: Variant)

@export var settings_path: String = "user://settings.json"
@export var settings_version: int = 1

# json stores the string, this maps to the godot enum
const WINDOW_MODES: Dictionary = {
	"windowed": DisplayServer.WINDOW_MODE_WINDOWED,
	"fullscreen": DisplayServer.WINDOW_MODE_FULLSCREEN,
	"borderless": DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
}

var default_settings: Dictionary = {
	"version": settings_version,
	"username": "change_me",
	"noray_relay_host": "home.ssebs.com",  # noray.casa.ssebs.com, 192.168.1.247
	"resolution": "1920x1080",
	"fullscreen_mode": "windowed",  # or "fullscreen" or "borderless"
	"bike_skin": "res://resources/entities/bikes/skins/sport_default_skin_definition.tres",
	"character_skin": "res://resources/entities/player/skins/biker_default_skin_definition.tres",
}

var current_settings: Dictionary


func _ready():
	if Engine.is_editor_hint():
		return

	self.call_deferred("deferred_init")


func deferred_init():
	if FileAccess.file_exists(settings_path):
		load_settings()
	else:
		save_default_settings()


func update_setting(
	key: String,
	value: Variant,
	should_emit_signal: bool = true,
	should_write_to_disk: bool = false,
):
	current_settings[key] = value
	if should_write_to_disk:
		save_settings()
	if should_emit_signal:
		setting_updated.emit(key, value)


## write current_settings to settings.json
func save_settings():
	DictJSONSaverLoader.save_json_to_file(settings_path, current_settings)


## load settings.json into current_settings
## emits all_settings_changed
func load_settings():
	var json_dict = DictJSONSaverLoader.load_json_from_file(settings_path)
	if json_dict == {}:
		printerr("failed to parse json from %s" % settings_path)
		return

	if json_dict["version"] != settings_version:
		printerr(
			"settings.json version mismatch, %s != %s" % [json_dict["version"], settings_version]
		)
		# TODO: migrate version
		return

	for key in default_settings.keys():
		current_settings[key] = json_dict.get(key, default_settings[key])

	all_settings_changed.emit(current_settings)


## save_settings() with default_settings
func save_default_settings():
	load_default_settings()
	save_settings()


## Load default_settings to current_settings
## emits all_settings_changed
func load_default_settings():
	current_settings = default_settings
	all_settings_changed.emit(current_settings)


## convert windowmode to string from WINDOW_MODES map
static func windowmode_to_str(wmode: int) -> String:
	match wmode:
		DisplayServer.WINDOW_MODE_WINDOWED:
			return "windowed"
		DisplayServer.WINDOW_MODE_FULLSCREEN:
			return "fullscreen"
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			return "borderless"
	return ""


## convert string to windowmode from WINDOW_MODES map
static func str_to_windowmode(mode_str: String) -> int:
	return WINDOW_MODES.get(mode_str, DisplayServer.WINDOW_MODE_WINDOWED)
