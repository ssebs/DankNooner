@tool
class_name PauseMenuState extends MenuState

@export var menu_manager: MenuManager

@onready var back_btn: Button = %BackBtn


func Enter(_state_context: StateContext):
	ui.show()
	back_btn.pressed.connect(_on_back_pressed)


func Exit(_state_context: StateContext):
	ui.hide()
	back_btn.pressed.disconnect(_on_back_pressed)


func _on_back_pressed():
	print("back pressed")
