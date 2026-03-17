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

## FMOD nodes (untyped to avoid parse errors on web)
var sounds_container: Node = null
var startup: Node = null
var ninja500_revs: Node = null
var fmod_manager: Node = null
var _is_web: bool = false

# TODO - use InputState to switch VCA/busses


func _ready():
	if Engine.is_editor_hint():
		return

	_is_web = OS.has_feature("web")

	if _is_web:
		print("AudioManager: Web platform detected, loading banks from preloaded VFS")
		# Remove FMOD scene nodes — we load banks manually on web
		for child in get_children():
			if child.get_class().begins_with("Fmod"):
				child.queue_free()
		_load_web_banks()
	else:
		# Initialize FMOD manager (moved from autoload for web compatibility)
		fmod_manager = load("res://addons/fmod/FmodManager.gd").new()
		fmod_manager.name = "FmodManager"
		add_child(fmod_manager)

	# Get FMOD node references
	sounds_container = get_node_or_null("%Sounds")
	startup = get_node_or_null("%Startup")
	ninja500_revs = get_node_or_null("%Ninja500Revs")

	# Apply initial volumes and connect for updates
	settings_manager.all_settings_changed.connect(_on_all_settings_changed)
	settings_manager.setting_updated.connect(_on_setting_updated)

	# Disable audio if arg is passed
	var args := OS.get_cmdline_user_args()
	if "--disable-audio" in args:
		_get_fmod_server().mute_all_events()


## Bank file names that get copied to dist/banks/ by FmodWebExportPlugin
const WEB_BANK_FILES: PackedStringArray = [
	"Master.strings.bank",  # Must be loaded first
	"Master.bank",
	"SFX.bank",
]


## Load banks from the preloaded VFS on web (files served from banks/ dir)
func _load_web_banks() -> void:
	var fmod_server = _get_fmod_server()
	for bank_file in WEB_BANK_FILES:
		var path := "banks/%s" % bank_file
		print("AudioManager: Loading web bank: %s" % path)
		fmod_server.load_bank(path, fmod_server.FMOD_STUDIO_LOAD_BANK_NORMAL)


func _get_fmod_server():
	return Engine.get_singleton("FmodServer")


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
	var fmod_server = _get_fmod_server()
	if fmod_server == null:
		return

	if vca_name == "MASTER":
		var master_bus = fmod_server.get_bus("bus:/")
		if master_bus == null:
			printerr("could not get fmod master bus")
			return
		master_bus.volume = volume
		return

	if !vca_name.contains("vca:/"):
		return

	var vca = fmod_server.get_vca(vca_name)
	if vca == null:
		printerr("could not load vca from name %s" % vca_name)
		return
	vca.volume = volume


func play_ninja500_revs():
	if ninja500_revs == null:
		return
	ninja500_revs.play()


func update_ninja500_rpm(val: float):
	if ninja500_revs == null:
		return
	ninja500_revs.set_parameter("RPM", val)


func play_startup():
	if startup == null:
		return
	startup.play()


func stop_all():
	if sounds_container == null:
		return
	for sound in sounds_container.get_children():
		if sound.get_class().begins_with("FmodEventEmitter"):
			sound.stop()
