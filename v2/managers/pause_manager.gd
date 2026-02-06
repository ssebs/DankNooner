@tool
class_name PauseManager extends BaseManager

signal pause_mode_changed(is_paused: bool)

var is_paused := false:
	set(val):
		is_paused = val
		pause_mode_changed.emit()


func _ready():
	if Engine.is_editor_hint():
		return

	manager_manager.input_manager.input_state_changed.connect(_on_input_state_changed)


func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("ui_cancel"):
		if is_paused:
			do_pause()
		else:
			do_unpause()


func _on_input_state_changed(new_state: InputManager.InputState):
	match new_state:
		InputManager.InputState.IN_MENU, InputManager.InputState.DISABLED:
			disable_input_and_processing()
		InputManager.InputState.IN_GAME:
			enable_input_and_processing()


func do_pause():
	pass


func do_unpause():
	pass
