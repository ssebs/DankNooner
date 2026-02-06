@tool
class_name InputManager extends BaseManager

signal input_state_changed(new_state: InputState)

enum InputState {
	IN_MENU,
	IN_GAME,
	DISABLED,
}

var current_input_state = InputState.IN_MENU:
	set(val):
		prev_input_state = current_input_state
		current_input_state = val
		showhide_mouse_cursor()
		input_state_changed.emit(val)

var prev_input_state: InputState = InputState.IN_MENU


## Shows or hides mouse cursor depending on current_input_state
func showhide_mouse_cursor():
	match current_input_state:
		InputManager.InputState.IN_MENU:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		InputManager.InputState.IN_GAME, InputManager.InputState.DISABLED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
