@tool
class_name HelpMenuState extends MenuState

@export var menu_manager: MenuManager

@onready var gamepad_btn: Button = %GamepadBtn
@onready var kbm_btn: Button = %KBMBtn
@onready var close_help_btn: Button = %CloseHelpBtn

@onready var gamepad_img: TextureRect = %GamepadImg
@onready var kbm_img: TextureRect = %KBMImg
@onready var bg_tint: ColorRect = %BGTint


func Enter(state_context: StateContext):
	return_ctx = state_context
	return_state = state_context.return_state

	if state_context is PauseStateContext:
		bg_tint.visible = state_context.show_bg_tint
	else:
		bg_tint.visible = false

	ui.show()
	_show_controls_for_current_device()

	gamepad_btn.pressed.connect(_on_gamepad_pressed)
	kbm_btn.pressed.connect(_on_kbm_pressed)
	close_help_btn.pressed.connect(_on_close_help_pressed)


func Exit(_state_context: StateContext):
	ui.hide()
	gamepad_btn.pressed.disconnect(_on_gamepad_pressed)
	kbm_btn.pressed.disconnect(_on_kbm_pressed)
	close_help_btn.pressed.disconnect(_on_close_help_pressed)


func _show_controls_for_current_device():
	if Input.get_connected_joypads().size() > 0:
		_on_gamepad_pressed()
	else:
		_on_kbm_pressed()


func _on_gamepad_pressed():
	gamepad_img.show()
	kbm_img.hide()


func _on_kbm_pressed():
	kbm_img.show()
	gamepad_img.hide()


func _on_close_help_pressed():
	transitioned.emit(return_state, StateContext.NewWithReturn(self))


#override
func on_cancel_key_pressed():
	_on_close_help_pressed()
