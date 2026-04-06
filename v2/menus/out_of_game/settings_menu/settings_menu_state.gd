@tool
class_name SettingsMenuState extends MenuState

@export var menu_manager: MenuManager
@export var settings_manager: SettingsManager
@export var main_menu_state: MenuState

@onready var back_btn: Button = %BackBtn
@onready var save_btn: Button = %SaveBtn
@onready var reset_btn: Button = %ResetBtn

@onready var signal_host_entry: LineEdit = %SignalHostEntry
@onready var window_mode_opt: OptionButton = %WindowModeOpt
@onready var master_vol_slider: HSlider = %MasterVolSlider
@onready var music_vol_slider: HSlider = %MusicVolSlider
@onready var sfx_vol_slider: HSlider = %SFXVolSlider
@onready var menu_vol_slider: HSlider = %MenuVolSlider

@onready var resolution_scale_label: Label = %RESOLUTION_SCALE_LABEL
@onready var resolution_scale: HSlider = %ResolutionScaleSlider
@onready var joy_cam_sens: HSlider = %JoyCamSensSlider
@onready var mouse_cam_sens: HSlider = %MouseCamSensSlider
@onready var invert_cam: CheckBox = %InvertCamCheck
## 0 is easy, 1 is hard. TODO make enum
@onready var difficulty_opt: OptionButton = %DifficultyOptBtn

@onready var bg_tint: ColorRect = %BGTint


func _ready():
	window_mode_opt.clear()
	for mode_str in SettingsManager.WINDOW_MODES.keys():
		window_mode_opt.add_item(
			tr(SettingsManager.WINDOW_MODE_LABELS[mode_str]), SettingsManager.WINDOW_MODES[mode_str]
		)


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
	back_btn.pressed.disconnect(_on_back_pressed)
	save_btn.pressed.disconnect(_on_save_pressed)
	reset_btn.pressed.disconnect(_on_reset_pressed)

	settings_manager.setting_updated.disconnect(_on_setting_updated)
	settings_manager.all_settings_changed.disconnect(_on_all_settings_changed)

	resolution_scale.value_changed.disconnect(_on_resolution_scale_changed)


func load_settings_into_ui():
	signal_host_entry.text = settings_manager.current_settings["signal_relay_host"]

	var wmode_id := SettingsManager.str_to_windowmode(
		settings_manager.current_settings["fullscreen_mode"]
	)
	for i in window_mode_opt.item_count:
		if window_mode_opt.get_item_id(i) == wmode_id:
			window_mode_opt.select(i)
			break

	master_vol_slider.value = settings_manager.current_settings["master_vol"]
	music_vol_slider.value = settings_manager.current_settings["music_vol"]
	sfx_vol_slider.value = settings_manager.current_settings["sfx_vol"]
	menu_vol_slider.value = settings_manager.current_settings["menu_vol"]

	resolution_scale.value = settings_manager.current_settings["resolution_scale"]
	_on_resolution_scale_changed(resolution_scale.value)
	joy_cam_sens.value = settings_manager.current_settings["joy_cam_sens"]
	mouse_cam_sens.value = settings_manager.current_settings["mouse_cam_sens"]
	invert_cam.button_pressed = settings_manager.current_settings["invert_cam"]
	difficulty_opt.selected = settings_manager.current_settings["difficulty"]


func _on_all_settings_changed(_current_settings: Dictionary):
	load_settings_into_ui()


func _on_setting_updated(_key: String, _value: Variant):
	load_settings_into_ui()


func _on_resolution_scale_changed(val: float):
	var s = "%.2f" % val
	resolution_scale_label.text = tr("RESOLUTION_SCALE_LABEL") % s.rstrip("0").rstrip(".")


func _on_save_pressed():
	settings_manager.update_setting("signal_relay_host", signal_host_entry.text, false)

	settings_manager.update_setting(
		"fullscreen_mode",
		SettingsManager.windowmode_to_str(window_mode_opt.get_selected_id()),
		false
	)

	settings_manager.update_setting("master_vol", master_vol_slider.value, false)
	settings_manager.update_setting("music_vol", music_vol_slider.value, false)
	settings_manager.update_setting("sfx_vol", sfx_vol_slider.value, false)
	settings_manager.update_setting("menu_vol", menu_vol_slider.value, false)

	settings_manager.update_setting("resolution_scale", resolution_scale.value, false)
	settings_manager.update_setting("joy_cam_sens", joy_cam_sens.value, false)
	settings_manager.update_setting("mouse_cam_sens", mouse_cam_sens.value, false)
	settings_manager.update_setting("invert_cam", invert_cam.button_pressed, false)
	settings_manager.update_setting("difficulty", difficulty_opt.selected, false)

	settings_manager.save_settings()

	UiToast.ShowToast(tr("SAVED_SETTINGS_LABEL"))


func _on_reset_pressed():
	settings_manager.load_default_settings()


func _on_back_pressed():
	transitioned.emit(return_state, StateContext.NewWithReturn(self))


#override
func on_cancel_key_pressed():
	_on_back_pressed()
