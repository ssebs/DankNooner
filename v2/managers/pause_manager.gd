@tool
class_name PauseManager extends BaseManager

@export var menu_manager: MenuManager
@export var level_manager: LevelManager
@export var input_manager: InputManager


func _ready():
	if Engine.is_editor_hint():
		return

	input_manager.pause_requested.connect(do_pause)
	input_manager.unpause_requested.connect(do_unpause)


func do_pause():
	input_manager.current_input_state = InputManager.InputState.IN_GAME_PAUSED
	menu_manager.switch_to_pause_menu()
	menu_manager.enable_input_and_processing()
	level_manager.disable_input_and_processing()


func do_unpause():
	input_manager.current_input_state = InputManager.InputState.IN_GAME
	menu_manager.hide_all_menus()
	menu_manager.disable_input_and_processing()
	level_manager.enable_input_and_processing()
