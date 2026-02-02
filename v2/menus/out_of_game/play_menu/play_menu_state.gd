@tool
class_name PlayMenuState extends MenuState

# SEE planning_docs\diagrams\play-menu-ui.excalidraw

@export var menu_manager: MenuManager
@export var main_menu_state: MenuState
@export var lobby_menu_state: MenuState
@export var customize_menu_state: MenuState

@onready var back_btn: Button = %BackBtn
@onready var lobby_btn: Button = %LobbyBtn
@onready var customize_btn: Button = %CustomizeBtn


func Enter():
	ui.show()
	back_btn.pressed.connect(_on_back_pressed)
	lobby_btn.pressed.connect(_on_lobby_pressed)
	customize_btn.pressed.connect(_on_customize_pressed)


func Exit():
	ui.hide()
	back_btn.pressed.disconnect(_on_back_pressed)
	lobby_btn.pressed.disconnect(_on_lobby_pressed)
	customize_btn.pressed.disconnect(_on_customize_pressed)


func _on_customize_pressed():
	transitioned.emit(customize_menu_state)


func _on_lobby_pressed():
	transitioned.emit(lobby_menu_state)


func _on_back_pressed():
	transitioned.emit(main_menu_state)
