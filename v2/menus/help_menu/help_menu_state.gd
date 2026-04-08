@tool
class_name HelpMenuState extends MenuState

@export var menu_manager: MenuManager

@onready var tab_container: TabContainer = %TabContainer
@onready var close_help_btn: Button = %CloseHelpBtn
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

	close_help_btn.pressed.connect(_on_close_help_pressed)


func Exit(_state_context: StateContext):
	ui.hide()
	close_help_btn.pressed.disconnect(_on_close_help_pressed)


func _show_controls_for_current_device():
	if Input.get_connected_joypads().size() > 0:
		tab_container.current_tab = 0
	else:
		tab_container.current_tab = 1


func _on_close_help_pressed():
	transitioned.emit(return_state, StateContext.NewWithReturn(self))


#override
func on_cancel_key_pressed():
	_on_close_help_pressed()
