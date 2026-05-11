@tool
class_name AudioManager extends BaseManager

@export var settings_manager: SettingsManager
@export_tool_button("Play Startup") var tool_btn_1 = play_startup

## Map of settings_manager key → audio bus name. Buses are defined in `default_bus_layout.tres`
## (must be created in the editor — runtime AudioServer.add_bus() doesn't work on web exports).
const VOLUME_SETTING_MAP: Dictionary = {
	"master_vol": "Master",
	"menu_vol": "Menu",
	"sfx_vol": "SFX",
	"music_vol": "Music",
}

# TODO - use InputState to switch which buses are routed where

var sounds_container: Node
var startup: SoundEvent
var ninja500_revs: EngineSoundEvent


func _ready():
	sounds_container = get_node_or_null("%Sounds")
	startup = get_node_or_null("%Startup") as SoundEvent
	ninja500_revs = get_node_or_null("%Ninja500Revs") as EngineSoundEvent

	if Engine.is_editor_hint():
		return

	settings_manager.all_settings_changed.connect(_on_all_settings_changed)
	settings_manager.setting_updated.connect(_on_setting_updated)

	var args := OS.get_cmdline_user_args()
	if "--disable-audio" in args:
		AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Master"), true)


func _on_all_settings_changed(new_settings: Dictionary):
	for setting_key in VOLUME_SETTING_MAP.keys():
		var bus_name: String = VOLUME_SETTING_MAP[setting_key]
		var setting_value: float = new_settings[setting_key]
		_apply_bus_volume(bus_name, setting_value)


func _on_setting_updated(setting_key: String, setting_value: Variant):
	if !VOLUME_SETTING_MAP.has(setting_key):
		return
	_apply_bus_volume(VOLUME_SETTING_MAP[setting_key], setting_value)


func _apply_bus_volume(bus_name: String, linear_volume: float):
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		DebugUtils.DebugErrMsg("audio bus not found: %s" % bus_name)
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(linear_volume))


func play_ninja500_revs():
	ninja500_revs.play()


func update_ninja500_rpm(val: float):
	ninja500_revs.set_parameter("RPM", val)


func play_startup():
	startup.play()


func stop_all():
	for sound in sounds_container.get_children():
		if sound is SoundEvent:
			sound.stop()
