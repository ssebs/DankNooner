@tool
class_name InputManager extends BaseManager

signal input_state_changed(new_state: InputState)
signal pause_requested
signal unpause_requested

enum InputState {
	IN_MENU,
	IN_GAME,
	IN_GAME_PAUSED,
	DISABLED,
}

@export var menu_manager: MenuManager

var current_input_state = InputState.IN_MENU:
	set(val):
		current_input_state = val
		showhide_mouse_cursor()
		input_state_changed.emit(val)


func _unhandled_input(event: InputEvent):
	match current_input_state:
		InputManager.InputState.DISABLED:
			return
		InputManager.InputState.IN_GAME:
			if event.is_action_pressed("pause"):
				pause_requested.emit()
		InputManager.InputState.IN_GAME_PAUSED:
			if event.is_action_pressed("pause"):
				unpause_requested.emit()
		InputManager.InputState.IN_MENU:
			if event.is_action_pressed("ui_cancel"):
				var current_state = menu_manager.state_machine.current_state as MenuState
				if current_state:
					current_state.on_cancel_key_pressed()


## Shows or hides mouse cursor depending on current_input_state
func showhide_mouse_cursor():
	match current_input_state:
		InputManager.InputState.IN_MENU, InputManager.InputState.IN_GAME_PAUSED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		InputManager.InputState.IN_GAME, InputManager.InputState.DISABLED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
