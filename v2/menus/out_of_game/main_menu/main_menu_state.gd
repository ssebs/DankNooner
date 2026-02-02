@tool
class_name MainMenuState extends MenuState

@export var menu_manager: MenuManager
@export var settings_menu_state: MenuState
@export var play_menu_state: MenuState
@export var customize_menu_state: MenuState

@onready var settings_btn: Button = %SettingsBtn
@onready var play_btn: Button = %PlayBtn
@onready var customize_btn: Button = %CustomizeBtn
@onready var quit_btn: Button = %QuitBtn


func Enter(_state_context: StateContext):
	ui.show()
	play_btn.pressed.connect(_on_play_btn_pressed)
	settings_btn.pressed.connect(_on_settings_btn_pressed)
	quit_btn.pressed.connect(_on_quit_btn_pressed)
	customize_btn.pressed.connect(_on_customize_btn_pressed)


func Exit(_state_context: StateContext):
	ui.hide()

	play_btn.pressed.disconnect(_on_play_btn_pressed)
	settings_btn.pressed.disconnect(_on_settings_btn_pressed)
	quit_btn.pressed.disconnect(_on_quit_btn_pressed)
	customize_btn.pressed.disconnect(_on_customize_btn_pressed)


func _on_customize_btn_pressed():
	transitioned.emit(customize_menu_state, null)


func _on_play_btn_pressed():
	transitioned.emit(play_menu_state, null)


func _on_settings_btn_pressed():
	transitioned.emit(settings_menu_state, null)


func _on_quit_btn_pressed():
	get_tree().quit(0)
