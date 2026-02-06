@tool
class_name PauseMenuState extends MenuState

@export var menu_manager: MenuManager
@export var level_manager: LevelManager
@export var input_manager: InputManager
@export var pause_manager: PauseManager

@export var main_menu_state: MenuState

@onready var resume_btn: Button = %ResumeBtn
@onready var main_menu_btn: Button = %MainMenuBtn
# @onready var back_btn: Button = %BackBtn

# See managers/pause_manager.gd


func Enter(_state_context: StateContext):
	ui.show()
	resume_btn.pressed.connect(_on_resume_pressed)
	main_menu_btn.pressed.connect(_on_main_menu_pressed)
	# back_btn.pressed.connect(_on_back_pressed)


func Exit(_state_context: StateContext):
	ui.hide()
	resume_btn.pressed.disconnect(_on_resume_pressed)
	main_menu_btn.pressed.disconnect(_on_main_menu_pressed)
	# back_btn.pressed.disconnect(_on_back_pressed)


func _on_resume_pressed():
	pause_manager.do_unpause()


func _on_main_menu_pressed():
	pause_manager.is_paused = false
	transitioned.emit(main_menu_state, null)
	input_manager.current_input_state = InputManager.InputState.IN_MENU
	level_manager.spawn_menu_level()


# func _on_back_pressed():
# 	print("back pressed")


#override
func on_cancel_key_pressed():
	_on_resume_pressed()
