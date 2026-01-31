@tool
class_name PlayMenuState extends MenuState

@export var menu_manager: MenuManager
@export var main_menu_state: MenuState
@export var lobby_menu_state: MenuState

@onready var back_btn: Button = %BackBtn
@onready var lobby_btn: Button = %LobbyBtn


func Enter():
	ui.show()
	back_btn.pressed.connect(_on_back_pressed)
	lobby_btn.pressed.connect(_on_lobby_pressed)


func Exit():
	ui.hide()
	back_btn.pressed.disconnect(_on_back_pressed)
	lobby_btn.pressed.disconnect(_on_lobby_pressed)


func _on_lobby_pressed():
	transitioned.emit(lobby_menu_state)


func _on_back_pressed():
	transitioned.emit(main_menu_state)
