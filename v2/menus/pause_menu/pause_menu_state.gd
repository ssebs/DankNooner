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
@export var help_menu_state: MenuState

@onready var resume_btn: Button = %ResumeBtn
@onready var main_menu_btn: Button = %MainMenuBtn
@onready var respawn_btn: Button = %RespawnBtn
@onready var cancel_event_btn: Button = %CancelEventBtn
@onready var customize_btn: Button = %CustomizeBtn
@onready var settings_btn: Button = %SettingsBtn
@onready var help_btn: Button = %HelpBtn
@onready var level_select_panel: LevelSelectPanel = %LevelSelectPanel

@onready var bg_tint: ColorRect = %BGTint

# See managers/pause_manager.gd


func Enter(_state_context: StateContext):
	ui.show()
	resume_btn.pressed.connect(_on_resume_pressed)
	main_menu_btn.pressed.connect(_on_main_menu_pressed)
	respawn_btn.pressed.connect(_on_respawn_pressed)
	cancel_event_btn.pressed.connect(_on_cancel_event_pressed)

	connection_manager.server_disconnected.connect(_on_server_disconnected)
	settings_btn.pressed.connect(_on_settings_pressed)
	customize_btn.pressed.connect(_on_customize_pressed)
	help_btn.pressed.connect(_on_help_pressed)

	# Host-only, and only meaningful when a non-FreeRoam event is active.
	cancel_event_btn.visible = (
		multiplayer.is_server()
		and gamemode_manager.current_game_mode != GameModeType.Kind.FREE_ROAM
	)

	# Host-only level switcher: lets the host swap maps without tearing down the lobby.
	level_select_panel.visible = multiplayer.is_server()
	if multiplayer.is_server():
		level_select_panel.populate(level_manager, gamemode_manager.current_level_name as int)
		level_select_panel.start_pressed.connect(_on_level_select_start_pressed)
		level_select_panel.level_selected.connect(_on_level_select_level_selected)
		_update_level_select_start_disabled()

	respawn_btn.call_deferred("grab_focus")


func Exit(_state_context: StateContext):
	ui.hide()
	resume_btn.pressed.disconnect(_on_resume_pressed)
	main_menu_btn.pressed.disconnect(_on_main_menu_pressed)
	respawn_btn.pressed.disconnect(_on_respawn_pressed)
	cancel_event_btn.pressed.disconnect(_on_cancel_event_pressed)

	connection_manager.server_disconnected.disconnect(_on_server_disconnected)
	settings_btn.pressed.disconnect(_on_settings_pressed)
	customize_btn.pressed.disconnect(_on_customize_pressed)
	help_btn.pressed.disconnect(_on_help_pressed)

	if level_select_panel.start_pressed.is_connected(_on_level_select_start_pressed):
		level_select_panel.start_pressed.disconnect(_on_level_select_start_pressed)
	if level_select_panel.level_selected.is_connected(_on_level_select_level_selected):
		level_select_panel.level_selected.disconnect(_on_level_select_level_selected)


func _on_help_pressed():
	transitioned.emit(help_menu_state, PauseStateContext.NewFromPause(self, true))


func _on_respawn_pressed():
	spawn_manager.respawn_player.rpc(multiplayer.get_unique_id())
	_on_resume_pressed()


func _on_cancel_event_pressed():
	gamemode_manager.change_gamemode.rpc_id(
		1, GameModeType.Kind.FREE_ROAM, multiplayer.get_unique_id()
	)
	_on_resume_pressed()


func _on_resume_pressed():
	pause_manager.do_unpause()


func _on_level_select_start_pressed():
	# Restart the match on the chosen level; the server (and lobby code) stays up.
	var level_id := level_select_panel.get_selected_level_id()
	pause_manager.do_unpause()
	gamemode_manager.start_game.rpc(level_id)


func _on_level_select_level_selected(_level_id: int):
	_update_level_select_start_disabled()


func _update_level_select_start_disabled():
	var selected_id := level_select_panel.get_selected_level_id()
	var current_id := gamemode_manager.current_level_name as int
	level_select_panel.set_start_disabled(selected_id == current_id)


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
