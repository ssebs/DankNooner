@tool
class_name PauseMenuState extends MenuState

@export var menu_manager: MenuManager
@export var connection_manager: ConnectionManager
@export var level_manager: LevelManager
@export var input_state_manager: InputStateManager
@export var pause_manager: PauseManager
@export var gamemode_manager: GamemodeManager
@export var spawn_manager: SpawnManager

@export var main_menu_state: MenuState
@export var settings_menu_state: MenuState
@export var customize_menu_state: MenuState

@onready var resume_btn: Button = %ResumeBtn
@onready var main_menu_btn: Button = %MainMenuBtn
@onready var respawn_btn: Button = %RespawnBtn
@onready var customize_btn: Button = %CustomizeBtn
@onready var settings_btn: Button = %SettingsBtn

@onready var bg_tint: ColorRect = %BGTint

# See managers/pause_manager.gd


func Enter(_state_context: StateContext):
	ui.show()
	resume_btn.pressed.connect(_on_resume_pressed)
	main_menu_btn.pressed.connect(_on_main_menu_pressed)
	respawn_btn.pressed.connect(_on_respawn_pressed)

	connection_manager.server_disconnected.connect(_on_server_disconnected)
	settings_btn.pressed.connect(_on_settings_pressed)
	customize_btn.pressed.connect(_on_customize_pressed)

	respawn_btn.call_deferred("grab_focus")


func Exit(_state_context: StateContext):
	ui.hide()
	resume_btn.pressed.disconnect(_on_resume_pressed)
	main_menu_btn.pressed.disconnect(_on_main_menu_pressed)
	respawn_btn.pressed.disconnect(_on_respawn_pressed)

	connection_manager.server_disconnected.disconnect(_on_server_disconnected)
	settings_btn.pressed.disconnect(_on_settings_pressed)
	customize_btn.pressed.disconnect(_on_customize_pressed)


func _on_respawn_pressed():
	spawn_manager.respawn_player.rpc_id(1, multiplayer.get_unique_id())


func _on_resume_pressed():
	pause_manager.do_unpause()


func _on_main_menu_pressed():
	connection_manager.disconnect_sp_or_mp()
	gamemode_manager.end_game()

	transitioned.emit(main_menu_state, null)
	input_state_manager.current_input_state = InputStateManager.InputState.IN_MENU
	level_manager.spawn_menu_level()


func _on_settings_pressed():
	transitioned.emit(settings_menu_state, SettingsStateContext.NewFromPause(self, true))


func _on_customize_pressed():
	transitioned.emit(customize_menu_state, PauseStateContext.NewFromPause(self, true))


func _on_server_disconnected():
	_on_main_menu_pressed()


# func _on_back_pressed():
# 	DebugUtils.DebugMsg("back pressed")


#override
func on_cancel_key_pressed():
	_on_resume_pressed()
