@tool
class_name PauseManager extends BaseManager

signal pause_mode_changed(is_paused: bool)

var is_paused := false:
	set(val):
		is_paused = val
		pause_mode_changed.emit(val)


func _ready():
	if Engine.is_editor_hint():
		return


func _unhandled_input(event: InputEvent):
	match manager_manager.input_manager.current_input_state:
		InputManager.InputState.DISABLED:
			return
		InputManager.InputState.IN_MENU:
			if (
				manager_manager.menu_manager.state_machine.current_state
				== manager_manager.menu_manager.pause_menu_state
			):
				if event.is_action_pressed("pause"):
					if is_paused:
						do_unpause()
					else:
						do_pause()
		InputManager.InputState.IN_GAME:
			if event.is_action_pressed("pause"):
				if is_paused:
					do_unpause()
				else:
					do_pause()


func do_pause():
	is_paused = true
	manager_manager.input_manager.current_input_state = InputManager.InputState.IN_MENU
	manager_manager.menu_manager.switch_to_pause_menu()
	manager_manager.menu_manager.enable_input_and_processing()
	manager_manager.level_manager.disable_input_and_processing()


func do_unpause():
	is_paused = false
	manager_manager.input_manager.current_input_state = InputManager.InputState.IN_GAME
	manager_manager.menu_manager.hide_all_menus()
	manager_manager.menu_manager.disable_input_and_processing()
	manager_manager.level_manager.enable_input_and_processing()
