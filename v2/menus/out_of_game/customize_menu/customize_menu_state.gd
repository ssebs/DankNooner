@tool
class_name CustomizeMenuState extends MenuState

@export var menu_manager: MenuManager
@export var play_menu_state: MenuState

@onready var back_btn: Button = %BackBtn


func Enter():
	ui.show()
	back_btn.pressed.connect(_on_back_pressed)


func Exit():
	ui.hide()
	back_btn.pressed.disconnect(_on_back_pressed)


func _on_back_pressed():
	transitioned.emit(play_menu_state)
