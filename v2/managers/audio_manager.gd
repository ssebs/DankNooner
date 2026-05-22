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

## Looping engine sounds driven by RPM. Used by BikeSkinDefinition.engine_sound_id
## to pick which sound `play_revs()` activates.
enum EngineSfx {
	NINJA500,
	GROM,
}

## Generic SFX id for callers (e.g. GameModeTasks) that need to play a sound
## without holding a typed ref to a specific SoundEvent. Add new entries here
## and a matching case in `play_sfx()`.
enum Sfx {
	STARTUP,
	BOWLING_CRASH,
	COUNTDOWN_3SEC,
	COUNTDOWN_5SEC,
	COUNTDOWN_LOOP,
	MENU_CLICK,
	MENU_ERR,
	MAXIMIZE,
	MINIMIZE,
	MOUSE_CLICK,
	CLUNK_GEAR_CHANGE,
}

# TODO - use InputState to switch which buses are routed where

var sounds_container: Node
var startup: SoundEvent
var ninja500_revs: EngineSoundEvent
var grom_revs: EngineSoundEvent
var bowling_crash: SoundEvent
var countdown_3sec: SoundEvent
var countdown_5sec: SoundEvent
var countdown_loop: SoundEvent
var menu_click: SoundEvent
var menu_err: SoundEvent
var maximize: SoundEvent
var minimize: SoundEvent
var mouse_click: SoundEvent
var clunk_gear_change: SoundEvent

## Map of EngineSfx → EngineSoundEvent node, populated in _ready.
var _engine_sounds: Dictionary = {}
## Currently-playing engine sound id, or -1 if none.
var _active_engine_sfx: int = -1


func _ready():
	sounds_container = get_node_or_null("%Sounds")
	startup = get_node_or_null("%Startup") as SoundEvent
	ninja500_revs = get_node_or_null("%Ninja500Revs") as EngineSoundEvent
	grom_revs = get_node_or_null("%GromRevs") as EngineSoundEvent
	bowling_crash = get_node_or_null("%BowlingCrash") as SoundEvent
	countdown_3sec = get_node_or_null("%Countdown3Sec") as SoundEvent
	countdown_5sec = get_node_or_null("%Countdown5Sec") as SoundEvent
	countdown_loop = get_node_or_null("%CountdownLoop") as SoundEvent
	menu_click = get_node_or_null("%MenuClick") as SoundEvent
	menu_err = get_node_or_null("%MenuErr") as SoundEvent
	maximize = get_node_or_null("%Maximize") as SoundEvent
	minimize = get_node_or_null("%Minimize") as SoundEvent
	mouse_click = get_node_or_null("%MouseClick") as SoundEvent
	clunk_gear_change = get_node_or_null("%ClunkGearChange") as SoundEvent

	_engine_sounds = {
		EngineSfx.NINJA500: ninja500_revs,
		EngineSfx.GROM: grom_revs,
	}

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


## Plays the engine sound configured by `bike_def`. Stops any previously-active
## engine sound first so two loops don't overlap when a player swaps bikes.
func play_revs(bike_def: BikeSkinDefinition):
	var sfx_id: int = bike_def.engine_sound_id
	if _active_engine_sfx != -1 and _active_engine_sfx != sfx_id:
		_engine_sounds[_active_engine_sfx].stop()
	var sound: EngineSoundEvent = _engine_sounds[sfx_id]
	sound.min_pitch = bike_def.engine_min_pitch
	sound.max_pitch = bike_def.engine_max_pitch
	sound.rpm_curve = bike_def.engine_rpm_pitch_curve
	sound.play()
	_active_engine_sfx = sfx_id


func stop_revs():
	if _active_engine_sfx == -1:
		return
	_engine_sounds[_active_engine_sfx].stop()
	_active_engine_sfx = -1


func update_revs_rpm(bike_def: BikeSkinDefinition, val: float):
	_engine_sounds[bike_def.engine_sound_id].set_parameter("RPM", val)


func play_startup():
	startup.play()


func play_bowling_crash():
	bowling_crash.play()


func play_countdown_3sec():
	countdown_3sec.play()


func play_countdown_5sec():
	countdown_5sec.play()


func play_countdown_loop():
	countdown_loop.play()


func play_menu_click():
	menu_click.play()


func play_menu_err():
	menu_err.play()


func play_maximize():
	maximize.play()


func play_minimize():
	minimize.play()


func play_mouse_click():
	mouse_click.play()


func play_clunk_gear_change():
	clunk_gear_change.play()


func play_sfx(id: Sfx):
	get_sound_event(id).play()


func stop_sfx(id: Sfx):
	get_sound_event(id).stop()


func get_sound_event(id: Sfx) -> SoundEvent:
	match id:
		Sfx.STARTUP:
			return startup
		Sfx.BOWLING_CRASH:
			return bowling_crash
		Sfx.COUNTDOWN_3SEC:
			return countdown_3sec
		Sfx.COUNTDOWN_5SEC:
			return countdown_5sec
		Sfx.COUNTDOWN_LOOP:
			return countdown_loop
		Sfx.MENU_CLICK:
			return menu_click
		Sfx.MENU_ERR:
			return menu_err
		Sfx.MAXIMIZE:
			return maximize
		Sfx.MINIMIZE:
			return minimize
		Sfx.MOUSE_CLICK:
			return mouse_click
		Sfx.CLUNK_GEAR_CHANGE:
			return clunk_gear_change
	push_error("AudioManager.get_sound_event: unhandled Sfx id %s" % id)
	return null


func stop_all():
	for sound in sounds_container.get_children():
		if sound is SoundEvent:
			sound.stop()
