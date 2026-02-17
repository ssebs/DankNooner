@tool
class_name PauseMenuState extends MenuState

@export var menu_manager: MenuManager
@export var multiplayer_manager: MultiplayerManager
@export var level_manager: LevelManager
@export var input_state_manager: InputStateManager
@export var pause_manager: PauseManager
@export var gamemode_manager: GamemodeManager

@export var main_menu_state: MenuState

@onready var resume_btn: Button = %ResumeBtn
@onready var main_menu_btn: Button = %MainMenuBtn
@onready var respawn_btn: Button = %RespawnBtn
# @onready var back_btn: Button = %BackBtn

# See managers/pause_manager.gd


func Enter(_state_context: StateContext):
	ui.show()
	resume_btn.pressed.connect(_on_resume_pressed)
	main_menu_btn.pressed.connect(_on_main_menu_pressed)
	respawn_btn.pressed.connect(_on_respawn_pressed)

	multiplayer_manager.server_disconnected.connect(_on_server_disconnected)
	# back_btn.pressed.connect(_on_back_pressed)


func Exit(_state_context: StateContext):
	ui.hide()
	resume_btn.pressed.disconnect(_on_resume_pressed)
	main_menu_btn.pressed.disconnect(_on_main_menu_pressed)
	respawn_btn.pressed.disconnect(_on_respawn_pressed)

	multiplayer_manager.server_disconnected.disconnect(_on_server_disconnected)
	# back_btn.pressed.disconnect(_on_back_pressed)


func _on_respawn_pressed():
	level_manager.respawn_player.rpc_id(1, multiplayer.get_unique_id())


func _on_resume_pressed():
	pause_manager.do_unpause()


func _on_main_menu_pressed():
	multiplayer_manager.disconnect_sp_or_mp()
	gamemode_manager.end_game()

	transitioned.emit(main_menu_state, null)
	input_state_manager.current_input_state = InputStateManager.InputState.IN_MENU
	level_manager.spawn_menu_level()


func _on_server_disconnected():
	_on_main_menu_pressed()


# func _on_back_pressed():
# 	print("back pressed")


#override
func on_cancel_key_pressed():
	_on_resume_pressed()
