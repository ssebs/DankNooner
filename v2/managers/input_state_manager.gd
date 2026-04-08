@tool
## Manages InputState (in menu or in game) + sends input signals
class_name InputStateManager extends BaseManager

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

# @export var debug_mobile := true
@export var debug_mobile := false

var current_input_state = InputState.IN_MENU:
	set(val):
		current_input_state = val
		showhide_mouse_cursor()
		input_state_changed.emit(val)

var is_mobile := false


func _ready():
	add_to_group(UtilsConstants.GROUPS["InputStateManager"], true)

	if OS.has_feature("mobile") or debug_mobile:
		is_mobile = true


func _input(event: InputEvent):
	# Web browsers require mouse capture to happen inside an input event callback
	if event is InputEventMouseButton and event.pressed:
		showhide_mouse_cursor()


#region InputState (in game vs in menu)
func _unhandled_input(event: InputEvent):
	match current_input_state:
		InputStateManager.InputState.DISABLED:
			return
		InputStateManager.InputState.IN_GAME:
			if event.is_action_pressed("pause"):
				pause_requested.emit()
		InputStateManager.InputState.IN_GAME_PAUSED:
			if event.is_action_pressed("pause"):
				unpause_requested.emit()
		InputStateManager.InputState.IN_MENU:
			if event.is_action_pressed("ui_cancel"):
				var current_state = menu_manager.state_machine.current_state as MenuState
				if current_state:
					current_state.on_cancel_key_pressed()


## Shows or hides mouse cursor depending on current_input_state
func showhide_mouse_cursor():
	match current_input_state:
		InputStateManager.InputState.IN_MENU, InputStateManager.InputState.IN_GAME_PAUSED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		InputStateManager.InputState.IN_GAME, InputStateManager.InputState.DISABLED:
			if !is_mobile:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

#endregion
