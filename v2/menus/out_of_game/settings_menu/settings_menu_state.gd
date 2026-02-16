@tool
class_name SettingsMenuState extends MenuState

@export var menu_manager: MenuManager
@export var settings_manager: SettingsManager
@export var main_menu_state: MenuState

@onready var back_btn: Button = %BackBtn
@onready var save_btn: Button = %SaveBtn
@onready var reset_btn: Button = %ResetBtn

@onready var username_entry: LineEdit = %UsernameEntry
@onready var noray_host_entry: LineEdit = %NorayHostEntry


func Enter(_state_context: StateContext):
	ui.show()
	back_btn.pressed.connect(_on_back_pressed)
	save_btn.pressed.connect(_on_save_pressed)
	reset_btn.pressed.connect(_on_reset_pressed)

	settings_manager.setting_updated.connect(_on_setting_updated)
	settings_manager.all_settings_changed.connect(_on_all_settings_changed)

	settings_manager.load_settings()


func Exit(_state_context: StateContext):
	ui.hide()
	back_btn.pressed.disconnect(_on_back_pressed)
	save_btn.pressed.disconnect(_on_save_pressed)
	reset_btn.pressed.disconnect(_on_reset_pressed)

	settings_manager.setting_updated.disconnect(_on_setting_updated)
	settings_manager.all_settings_changed.disconnect(_on_all_settings_changed)


func load_settings_into_ui():
	username_entry.text = settings_manager.current_settings["username"]
	noray_host_entry.text = settings_manager.current_settings["noray_relay_host"]


func _on_all_settings_changed(_current_settings: Dictionary):
	load_settings_into_ui()


func _on_setting_updated(_key: String, _value: Variant):
	load_settings_into_ui()


func _on_save_pressed():
	settings_manager.update_setting("username", username_entry.text, false)
	settings_manager.update_setting("noray_relay_host", noray_host_entry.text, false)
	settings_manager.save_settings()

	UiToast.ShowToast(tr("SAVED_SETTINGS_LABEL"))


func _on_reset_pressed():
	settings_manager.load_default_settings()


func _on_back_pressed():
	transitioned.emit(main_menu_state, null)


#override
func on_cancel_key_pressed():
	_on_back_pressed()
