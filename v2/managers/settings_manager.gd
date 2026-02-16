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
	"username": "",
	"noray_relay_host": "home.ssebs.com",  # noray.casa.ssebs.com, 192.168.1.247
	"resolution": "1920x1080",
	"fullscreen_mode": "windowed"  # or "fullscreen" or "borderless"
}

var current_settings: Dictionary


func _ready():
	if Engine.is_editor_hint():
		return

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
	var file = FileAccess.open(settings_path, FileAccess.WRITE)
	if file == null:
		printerr("failed to open %s" % settings_path)
		return

	var json_str = JSON.stringify(current_settings)
	file.store_string(json_str)
	file.close()


## load settings.json into current_settings
## emits all_settings_changed
func load_settings():
	var file = FileAccess.open(settings_path, FileAccess.READ)
	if file == null:
		printerr("failed to open %s" % settings_path)
		return

	var json_dict = JSON.parse_string(file.get_as_text())
	if json_dict == null:
		printerr("failed to parse json from %s" % settings_path)
		return
	file.close()

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
