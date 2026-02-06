@tool
class_name PauseManager extends BaseManager

signal pause_mode_changed(is_paused: bool)

@export var menu_manager: MenuManager
@export var level_manager: LevelManager
@export var input_manager: InputManager

var is_paused := false:
	set(val):
		is_paused = val
		pause_mode_changed.emit(val)


func _ready():
	if Engine.is_editor_hint():
		return


func _unhandled_input(event: InputEvent):
	match input_manager.current_input_state:
		InputManager.InputState.DISABLED:
			return
		InputManager.InputState.IN_MENU:
			if menu_manager.state_machine.current_state == menu_manager.pause_menu_state:
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
	input_manager.current_input_state = InputManager.InputState.IN_MENU
	menu_manager.switch_to_pause_menu()
	menu_manager.enable_input_and_processing()
	level_manager.disable_input_and_processing()


func do_unpause():
	is_paused = false
	input_manager.current_input_state = InputManager.InputState.IN_GAME
	menu_manager.hide_all_menus()
	menu_manager.disable_input_and_processing()
	level_manager.enable_input_and_processing()
