@tool
class_name SplashMenuState extends MenuState

@export var menu_manager: MenuManager
@export var main_menu_state: MenuState

@export var debug_skip_ok: bool = true

@onready var splashes_to_show: Control = %SplashesToShow
@onready var timer: Timer = %Timer


func Enter(_state_context: StateContext):
	ui.show()
	# back_btn.pressed.connect(_on_back_pressed)


func Exit(_state_context: StateContext):
	ui.hide()
	# back_btn.pressed.disconnect(_on_back_pressed)


# func _on_back_pressed():
# 	transitioned.emit(menu_manager.prev_state, null)


#override
func on_cancel_key_pressed():
	pass
	# transitioned.emit(menu_manager.
