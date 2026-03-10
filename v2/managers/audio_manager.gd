@tool
class_name AudioManager extends BaseManager

@export var settings_manager: SettingsManager
@export_tool_button("Play Startup") var tool_btn_1 = play_startup

## map of settings_manager's key to the vca name from vca.get_path()
const VCA_SETTING_MAP: Dictionary = {
	"master_vol": "MASTER",
	"menu_vol": "vca:/Menu",
	"sfx_vol": "vca:/SFX",
	"music_vol": "vca:/Music",
}

@onready var sounds_container: Node = %Sounds
@onready var startup: FmodEventEmitter3D = %Startup
@onready var ninja500_revs: FmodEventEmitter3D = %Ninja500Revs

# TODO - use InputState to switch VCA/busses


func _ready():
	if Engine.is_editor_hint():
		return

	# # Set volume buses
	# for vca in FmodServer.get_all_vca():
	# 	vca = vca as FmodVCA
	# 	# vca.volume
	# 	print(vca.get_path())

	# for bus in FmodServer.get_all_buses():
	# 	bus = bus as FmodBus
	# 	print(bus.get_path())

	# Apply initial volumes and connect for updates
	settings_manager.all_settings_changed.connect(_on_all_settings_changed)
	settings_manager.setting_updated.connect(_on_setting_updated)

	# Disable audio if arg is passed
	var args := OS.get_cmdline_user_args()
	if "--disable-audio" in args:
		FmodServer.mute_all_events()


func _on_all_settings_changed(new_settings: Dictionary):
	for setting_name_str in VCA_SETTING_MAP.keys():
		var mapped_vca_name: String = VCA_SETTING_MAP[setting_name_str]
		var setting_value: float = new_settings[setting_name_str]
		_apply_vca_volume(mapped_vca_name, setting_value)


func _on_setting_updated(setting_key: String, setting_value: Variant):
	# Check if this setting maps to a VCA
	if !VCA_SETTING_MAP.has(setting_key):
		return

	var vca_name: String = VCA_SETTING_MAP[setting_key]
	if vca_name == null:
		printerr("could not find vca name %s" % vca_name)
		return

	_apply_vca_volume(vca_name, setting_value)


## vca_name should be in `vca:/NAME` format, or `MASTER`
func _apply_vca_volume(vca_name: String, volume: float):
	if vca_name == "MASTER":
		var master_bus: FmodBus = FmodServer.get_bus("bus:/")
		if master_bus == null:
			printerr("could not get fmod master bus")
			return
		master_bus.volume = volume
		return

	if !vca_name.contains("vca:/"):
		return

	var vca: FmodVCA = FmodServer.get_vca(vca_name)
	if vca == null:
		printerr("could not load vca from name %s" % vca_name)
		return
	vca.volume = volume


func play_ninja500_revs():
	ninja500_revs.play()


func update_ninja500_rpm(val: float):
	ninja500_revs.set_parameter("RPM", val)


func play_startup():
	startup.play()


func stop_all():
	for sound in sounds_container.get_children():
		if sound is FmodEventEmitter3D || sound is FmodEventEmitter2D:
			sound.stop()
