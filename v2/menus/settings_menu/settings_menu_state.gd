@tool
class_name SettingsMenuState extends MenuState

@export var menu_manager: MenuManager
@export var settings_manager: SettingsManager
@export var main_menu_state: MenuState

## Settings keys each tab's Reset restores, by tab index. Controls reset through ControlsTab.
const TAB_SETTING_KEYS: Array = [
	["signal_relay_host", "resolution_scale", "gamma", "fullscreen_mode", "vsync", "language"],
	["master_vol", "music_vol", "sfx_vol", "menu_vol", "mute", "mute_unfocused"],
	["difficulty", "joy_cam_sens", "mouse_cam_sens", "invert_cam", "auto_transmission"],
]

@onready var back_btn: Button = %BackBtn
@onready var save_btn: Button = %SaveBtn
@onready var reset_btn: Button = %ResetBtn
@onready var tab_container: TabContainer = %TabContainer
@onready var controls_tab: ControlsTab = %Controls

@onready var signal_host_entry: LineEdit = %SignalHostEntry
@onready var window_mode_opt: OptionButton = %WindowModeOpt
@onready var vsync_check: CheckBox = %VSyncCheck
@onready var language_opt: OptionButton = %LanguageOpt
@onready var master_vol_slider: HSlider = %MasterVolSlider
@onready var music_vol_slider: HSlider = %MusicVolSlider
@onready var sfx_vol_slider: HSlider = %SFXVolSlider
@onready var menu_vol_slider: HSlider = %MenuVolSlider
@onready var mute_check: CheckBox = %MuteCheck
@onready var mute_unfocused_check: CheckBox = %MuteUnfocusedCheck

@onready var resolution_scale_label: Label = %RESOLUTION_SCALE_LABEL
@onready var resolution_scale: HSlider = %ResolutionScaleSlider
@onready var gamma_slider: HSlider = %GammaSlider
@onready var joy_cam_sens: HSlider = %JoyCamSensSlider
@onready var mouse_cam_sens: HSlider = %MouseCamSensSlider
@onready var invert_cam: CheckBox = %InvertCamCheck
@onready var auto_transmission: CheckBox = %AutoTransmissionCheck
## 0 is easy, 1 is hard. TODO make enum
@onready var difficulty_opt: OptionButton = %DifficultyOptBtn

@onready var bg_tint: ColorRect = %BGTint


func _ready():
	super._ready()
	window_mode_opt.clear()
	# Raw keys: OptionButton auto-translates, so items follow a language change
	for mode_str in SettingsManager.WINDOW_MODES.keys():
		window_mode_opt.add_item(
			SettingsManager.WINDOW_MODE_LABELS[mode_str], SettingsManager.WINDOW_MODES[mode_str]
		)

	language_opt.clear()
	for locale in TranslationServer.get_loaded_locales():
		language_opt.add_item(TranslationServer.get_locale_name(locale))
		language_opt.set_item_metadata(language_opt.item_count - 1, locale)


func Enter(state_context: StateContext):
	return_ctx = state_context
	return_state = state_context.return_state

	if state_context is SettingsStateContext:
		bg_tint.visible = state_context.show_bg_tint
	else:
		bg_tint.visible = false

	ui.show()
	back_btn.pressed.connect(_on_back_pressed)
	save_btn.pressed.connect(_on_save_pressed)
	reset_btn.pressed.connect(_on_reset_pressed)

	settings_manager.setting_updated.connect(_on_setting_updated)
	settings_manager.all_settings_changed.connect(_on_all_settings_changed)

	resolution_scale.value_changed.connect(_on_resolution_scale_changed)

	settings_manager.load_settings()


func Exit(_state_context: StateContext):
	ui.hide()
	controls_tab.stop_listening()
	back_btn.pressed.disconnect(_on_back_pressed)
	save_btn.pressed.disconnect(_on_save_pressed)
	reset_btn.pressed.disconnect(_on_reset_pressed)

	settings_manager.setting_updated.disconnect(_on_setting_updated)
	settings_manager.all_settings_changed.disconnect(_on_all_settings_changed)

	resolution_scale.value_changed.disconnect(_on_resolution_scale_changed)


## Polled rather than wiring every widget's change signal.
func Update(_delta: float):
	save_btn.text = tr("SAVE_LABEL") + (" *" if _is_dirty() else "")


func show_controls_tab():
	tab_container.current_tab = tab_container.get_tab_idx_from_control(controls_tab)


func load_settings_into_ui(settings: Dictionary):
	signal_host_entry.text = settings["signal_relay_host"]

	var wmode_id := SettingsManager.str_to_windowmode(settings["fullscreen_mode"])
	for i in window_mode_opt.item_count:
		if window_mode_opt.get_item_id(i) == wmode_id:
			window_mode_opt.select(i)
			break
	vsync_check.button_pressed = settings["vsync"]

	for i in language_opt.item_count:
		if language_opt.get_item_metadata(i) == settings["language"]:
			language_opt.select(i)
			break

	master_vol_slider.value = settings["master_vol"]
	music_vol_slider.value = settings["music_vol"]
	sfx_vol_slider.value = settings["sfx_vol"]
	menu_vol_slider.value = settings["menu_vol"]
	mute_check.button_pressed = settings["mute"]
	mute_unfocused_check.button_pressed = settings["mute_unfocused"]

	resolution_scale.value = settings["resolution_scale"]
	_on_resolution_scale_changed(resolution_scale.value)
	gamma_slider.value = settings["gamma"]
	joy_cam_sens.value = settings["joy_cam_sens"]
	mouse_cam_sens.value = settings["mouse_cam_sens"]
	invert_cam.button_pressed = settings["invert_cam"]
	auto_transmission.button_pressed = settings["auto_transmission"]
	difficulty_opt.selected = settings["difficulty"]


## Every TAB_SETTING_KEYS value as currently shown in the UI.
func _settings_from_ui() -> Dictionary:
	return {
		"signal_relay_host": signal_host_entry.text,
		"fullscreen_mode": SettingsManager.windowmode_to_str(window_mode_opt.get_selected_id()),
		"vsync": vsync_check.button_pressed,
		"language": language_opt.get_item_metadata(language_opt.selected),
		"master_vol": master_vol_slider.value,
		"music_vol": music_vol_slider.value,
		"sfx_vol": sfx_vol_slider.value,
		"menu_vol": menu_vol_slider.value,
		"mute": mute_check.button_pressed,
		"mute_unfocused": mute_unfocused_check.button_pressed,
		"resolution_scale": resolution_scale.value,
		"gamma": gamma_slider.value,
		"joy_cam_sens": joy_cam_sens.value,
		"mouse_cam_sens": mouse_cam_sens.value,
		"invert_cam": invert_cam.button_pressed,
		"auto_transmission": auto_transmission.button_pressed,
		"difficulty": difficulty_opt.selected,
	}


func _is_dirty() -> bool:
	if controls_tab.is_dirty():
		return true
	var ui_settings := _settings_from_ui()
	for key in ui_settings:
		var saved = settings_manager.current_settings[key]
		# Sliders snap, and JSON loads every number as a float
		if ui_settings[key] is float or saved is float:
			if not is_equal_approx(ui_settings[key], saved):
				return true
		elif ui_settings[key] != saved:
			return true
	return false


func _on_all_settings_changed(current_settings: Dictionary):
	load_settings_into_ui(current_settings)
	controls_tab.load_controls(current_settings["controls"])


func _on_setting_updated(_key: String, _value: Variant):
	load_settings_into_ui(settings_manager.current_settings)


func _on_resolution_scale_changed(val: float):
	var s = "%.2f" % val
	resolution_scale_label.text = tr("RESOLUTION_SCALE_LABEL").format({"scale": s.rstrip("0").rstrip(".")})


func _on_save_pressed():
	var ui_settings := _settings_from_ui()
	for key in ui_settings:
		settings_manager.update_setting(key, ui_settings[key], false)
	settings_manager.update_setting("controls", controls_tab.get_pending(), false)
	settings_manager.save_settings()

	UiToast.ShowToast(tr("SAVED_SETTINGS_LABEL"))


## Resets only the current tab, in the UI. Still needs Save.
func _on_reset_pressed():
	if tab_container.get_current_tab_control() == controls_tab:
		controls_tab.reset()
		return
	var ui_settings := _settings_from_ui()
	for key in TAB_SETTING_KEYS[tab_container.current_tab]:
		ui_settings[key] = settings_manager.default_settings[key]
	load_settings_into_ui(ui_settings)


func _on_back_pressed():
	transitioned.emit(return_state, StateContext.NewWithReturn(self))


#override
func on_cancel_key_pressed():
	_on_back_pressed()


#override
func on_tab_key_pressed(dir: int):
	tab_container.current_tab = wrapi(tab_container.current_tab + dir, 0, tab_container.get_tab_count())
