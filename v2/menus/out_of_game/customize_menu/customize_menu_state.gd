@tool
class_name CustomizeMenuState extends MenuState

@export var menu_manager: MenuManager
@export var play_menu_state: MenuState

@onready var back_btn: Button = %BackBtn


func Enter(_state_context: StateContext):
	ui.show()
	back_btn.pressed.connect(_on_back_pressed)


func Exit(_state_context: StateContext):
	ui.hide()
	back_btn.pressed.disconnect(_on_back_pressed)


func _on_back_pressed():
	transitioned.emit(menu_manager.prev_state, null)

#override
func on_cancel_key_pressed():
	_on_back_pressed()
