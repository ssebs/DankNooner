@tool
class_name MainMenuState extends MenuState

@export var menu_manager: MenuManager
@export var settings_menu_state: MenuState
@export var play_menu_state: MenuState

@onready var settings_btn: Button = %SettingsBtn
@onready var play_btn: Button = %PlayBtn
@onready var quit_btn: Button = %QuitBtn


func Enter():
	ui.show()
	play_btn.pressed.connect(_on_play_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)


func Exit():
	ui.hide()

	play_btn.pressed.connect(_on_play_pressed)
	settings_btn.pressed.disconnect(_on_settings_pressed)
	quit_btn.pressed.disconnect(_on_quit_pressed)


func _on_play_pressed():
	transitioned.emit(play_menu_state)


func _on_settings_pressed():
	transitioned.emit(settings_menu_state)


func _on_quit_pressed():
	get_tree().quit(0)
