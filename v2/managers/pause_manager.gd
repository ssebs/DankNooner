@tool
class_name PauseManager extends BaseManager

@export var menu_manager: MenuManager
@export var level_manager: LevelManager
@export var input_state_manager: InputStateManager


func _ready():
	if Engine.is_editor_hint():
		return

	input_state_manager.pause_requested.connect(do_pause)
	input_state_manager.unpause_requested.connect(do_unpause)


func do_pause():
	input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME_PAUSED
	menu_manager.switch_to_pause_menu()
	menu_manager.enable_input_and_processing()
	level_manager.disable_input_and_processing()


func do_unpause():
	input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME
	menu_manager.hide_all_menus()
	menu_manager.disable_input_and_processing()
	level_manager.enable_input_and_processing()
