@tool
class_name LobbyMenuState extends MenuState

@export var menu_manager: MenuManager
@export var settings_manager: SettingsManager
@export var connection_manager: ConnectionManager
@export var lobby_manager: LobbyManager
@export var level_manager: LevelManager
@export var input_state_manager: InputStateManager
@export var gamemode_manager: GamemodeManager
@export var save_manager: SaveManager

@export var play_menu_state: MenuState
@export var customize_menu_state: MenuState

@onready var singleplayer_ui: Control = %SingleplayerUI
@onready var multiplayer_ui: Control = %MultiplayerUI

@onready var back_btn: Button = %BackBtn
@onready var level_select_panel: LevelSelectPanel = %LevelSelectPanel
@onready var customize_btn: Button = %CustomizeBtn

@onready var ip_label: Label = %IPLabel
@onready var ip_copy_btn: Button = %IPCopyBtn
# @onready var invite_btn: Button = %InviteBtn
@onready var player_list: VBoxContainer = %PlayersList  # PlayerListUI script
@onready var loading_ui: ColorRect = %LoadingUI
@onready var timeout_timer: Timer = %TimeoutTimer


#region state lifecycle
func Enter(state_context: StateContext):
	if state_context is not LobbyStateContext:
		DebugUtils.DebugErrMsg(
			"Must pass LobbyStateContext type when transitioning to LobbyMenuState"
		)
		return

	return_ctx = state_context
	return_state = state_context.return_state

	ui.show()
	loading_ui.hide()

	back_btn.pressed.connect(_on_back_pressed)
	level_select_panel.start_pressed.connect(_on_start_pressed)
	level_select_panel.level_selected.connect(_on_level_selected)
	ip_copy_btn.pressed.connect(_on_ip_copy_btn_pressed)
	customize_btn.pressed.connect(_on_customize_pressed)

	# Connection signals
	connection_manager.server_disconnected.connect(_on_server_disconnected)
	connection_manager.game_id_set.connect(_on_game_id_set)
	connection_manager.client_connection_failed.connect(_on_client_connection_failed)
	connection_manager.client_connection_succeeded.connect(_on_client_connection_succeeded)

	# Lobby signals
	lobby_manager.lobby_players_updated.connect(_on_lobby_players_updated)

	timeout_timer.timeout.connect(_on_timeout)

	level_select_panel.populate(level_manager, 1)
	set_single_or_multiplayer_ui()


func Exit(_state_context: StateContext):
	ui.hide()
	# return_ctx = null
	player_list.clear()

	back_btn.pressed.disconnect(_on_back_pressed)
	level_select_panel.start_pressed.disconnect(_on_start_pressed)
	level_select_panel.level_selected.disconnect(_on_level_selected)
	ip_copy_btn.pressed.disconnect(_on_ip_copy_btn_pressed)
	customize_btn.pressed.disconnect(_on_customize_pressed)

	connection_manager.server_disconnected.disconnect(_on_server_disconnected)
	connection_manager.game_id_set.disconnect(_on_game_id_set)
	connection_manager.client_connection_failed.disconnect(_on_client_connection_failed)
	connection_manager.client_connection_succeeded.disconnect(_on_client_connection_succeeded)

	lobby_manager.lobby_players_updated.disconnect(_on_lobby_players_updated)

	timeout_timer.timeout.disconnect(_on_timeout)
	timeout_timer.stop()


#endregion


#region button handlers (can call rpc)
## server only, calls rpc for all
func _on_level_selected(_level_id: int):
	if multiplayer.multiplayer_peer && multiplayer.is_server():
		level_select_panel.set_start_disabled(false)
		share_selected_level_with_clients.rpc(level_select_panel.get_selected_index())


## server only, calls rpc for all
func _on_start_pressed():
	if multiplayer.multiplayer_peer && multiplayer.is_server():
		gamemode_manager.start_game.rpc(level_select_panel.get_selected_level_id())


## cleanup before going back
func _on_back_pressed():
	connection_manager.disconnect_sp_or_mp()
	player_list.clear()

	if level_manager.current_level_name != LevelManager.LevelName.BG_GRAY_LEVEL:
		level_manager.spawn_menu_level()

	transitioned.emit(return_state, return_ctx)


## copy game id to clipboard
func _on_ip_copy_btn_pressed():
	DisplayServer.clipboard_set(ip_label.text)
	UiToast.ShowToast("Game ID copied to clipboard!")


func _on_customize_pressed():
	# transitioned.emit(customize_menu_state, return_ctx)
	transitioned.emit(
		customize_menu_state, StateContext.NewWithReturnAndContext(return_state, return_ctx)
	)


#endregion


#region network signal handlers
## set game join id in ui & enable clipboard btn
func _on_game_id_set(conn_addr: String):
	ip_label.text = conn_addr
	ip_copy_btn.disabled = false
	level_select_panel.refresh_preview()

	if (
		multiplayer.multiplayer_peer
		&& multiplayer.is_server()
		&& return_ctx.mode != LobbyStateContext.Mode.FREEROAM
	):
		call_deferred("_on_ip_copy_btn_pressed")


## set player list from server's lobby_players
func _on_lobby_players_updated(players: Dictionary):
	player_list.update_from_dict(players)


func _on_server_disconnected():
	UiToast.ShowToast("Server disconnected")
	_on_back_pressed()


func _on_client_connection_failed(reason: String):
	UiToast.ShowToast("Connection failed: %s" % reason, UiToast.ToastLevel.ERR)
	_on_back_pressed()


func _on_client_connection_succeeded(peer_id: int):
	loading_ui.hide()
	timeout_timer.stop()
	if !multiplayer.is_server():
		level_select_panel.set_controls_disabled(true)

	var player_def = save_manager.get_player_definition()
	lobby_manager.update_player_metadata.rpc_id(1, peer_id, player_def.to_dict())


func _on_timeout():
	UiToast.ShowToast("Connection timed out", UiToast.ToastLevel.ERR)
	_on_back_pressed()


#endregion

#region local RPCs
@rpc("call_local", "reliable")
func share_selected_level_with_clients(idx: int):
	level_select_panel.set_selected_index(idx)


#endregion


## Hide or Show the singleplayer / multiplayer ui depending on return_ctx.mode
func set_single_or_multiplayer_ui():
	# Reset controls disabled by a prior client join — otherwise re-entering as
	# host/freeroam leaves the start + level select buttons stuck disabled.
	level_select_panel.set_controls_disabled(false)

	match return_ctx.mode:
		LobbyStateContext.Mode.FREEROAM:
			multiplayer_ui.hide()
			singleplayer_ui.show()
			# ENet doesn't work on web — use WebRTC there
			if OS.has_feature("web"):
				connection_manager.connection_mode = ConnectionManager.ConnectionMode.WEBRTC
			else:
				connection_manager.connection_mode = ConnectionManager.ConnectionMode.IP_PORT
			await connection_manager.start_server()
			level_select_panel.grab_start_focus()
		_:
			singleplayer_ui.hide()
			multiplayer_ui.show()
			loading_ui.show()
			timeout_timer.start()
			level_select_panel.set_start_disabled(false)

	level_select_panel.call_deferred("refresh_preview")


#override
func on_cancel_key_pressed():
	_on_back_pressed()


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if menu_manager == null:
		issues.append("menu_manager must not be empty")
	if connection_manager == null:
		issues.append("connection_manager must not be empty")
	if lobby_manager == null:
		issues.append("lobby_manager must not be empty")
	if level_manager == null:
		issues.append("level_manager must not be empty")
	if input_state_manager == null:
		issues.append("input_state_manager must not be empty")
	if settings_manager == null:
		issues.append("settings_manager must not be empty")
	if gamemode_manager == null:
		issues.append("gamemode_manager must not be empty")
	if save_manager == null:
		issues.append("save_manager must not be empty")
	if customize_menu_state == null:
		issues.append("customize_menu_state must not be empty")
	if play_menu_state == null:
		issues.append("play_menu_state must not be empty")

	return issues
