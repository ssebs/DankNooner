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
@export var steam_manager: SteamManager

@export var play_menu_state: MenuState
@export var customize_menu_state: MenuState

const AUTO_HOST_LOBBY_SIZE := 2

@onready var singleplayer_ui: Control = %SingleplayerUI
@onready var multiplayer_ui: Control = %MultiplayerUI

@onready var back_btn: Button = %BackBtn
@onready var level_select_panel: LevelSelectPanel = %LevelSelectPanel
@onready var customize_btn: Button = %CustomizeBtn

@onready var lobby_panel: LobbyPanel = %LobbyPanel
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
	if return_state == self:
		# Returning from customize — _on_customize_pressed pointed our own context's
		# return_state back here so customize's Back lands in the lobby (leaving via the
		# play menu re-hosts and drops every connected client). Restore the real back target.
		return_state = play_menu_state
		return_ctx.return_state = play_menu_state

	ui.show()
	loading_ui.hide()

	back_btn.pressed.connect(_on_back_pressed)
	level_select_panel.start_pressed.connect(_on_start_pressed)
	level_select_panel.level_selected.connect(_on_level_selected)
	customize_btn.pressed.connect(_on_customize_pressed)
	lobby_manager.lobby_players_updated.connect(_on_lobby_players_updated)

	# Connection signals
	connection_manager.server_disconnected.connect(_on_server_disconnected)
	connection_manager.game_id_set.connect(_on_game_id_set)
	connection_manager.client_connection_failed.connect(_on_client_connection_failed)
	connection_manager.client_connection_succeeded.connect(_on_client_connection_succeeded)

	timeout_timer.timeout.connect(_on_timeout)

	# Only the host owns the Steam lobby friends get invited to
	lobby_panel.open(
		connection_manager, lobby_manager, steam_manager,
		return_ctx.mode == LobbyStateContext.Mode.HOST
	)

	level_select_panel.populate(level_manager, 1)
	set_single_or_multiplayer_ui()


func Exit(_state_context: StateContext):
	ui.hide()
	# return_ctx = null
	lobby_panel.close()

	back_btn.pressed.disconnect(_on_back_pressed)
	level_select_panel.start_pressed.disconnect(_on_start_pressed)
	level_select_panel.level_selected.disconnect(_on_level_selected)
	customize_btn.pressed.disconnect(_on_customize_pressed)
	lobby_manager.lobby_players_updated.disconnect(_on_lobby_players_updated)

	connection_manager.server_disconnected.disconnect(_on_server_disconnected)
	connection_manager.game_id_set.disconnect(_on_game_id_set)
	connection_manager.client_connection_failed.disconnect(_on_client_connection_failed)
	connection_manager.client_connection_succeeded.disconnect(_on_client_connection_succeeded)

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

	if level_manager.current_level_name != LevelManager.LevelName.BG_GRAY_LEVEL:
		level_manager.spawn_menu_level()

	transitioned.emit(return_state, return_ctx)


func _on_customize_pressed():
	# Customize's Back must return HERE (session stays up) — Enter() restores the
	# original back target when it sees return_state == self.
	transitioned.emit(
		customize_menu_state, StateContext.NewWithReturnAndContext(self, return_ctx)
	)


#endregion


#region network signal handlers
## LobbyPanel shows the ID; auto-copy it for the host
func _on_game_id_set(_conn_addr: String):
	level_select_panel.refresh_preview()

	if (
		multiplayer.multiplayer_peer
		&& multiplayer.is_server()
		&& return_ctx.mode != LobbyStateContext.Mode.FREEROAM
	):
		lobby_panel.copy_game_id.call_deferred()


func _on_server_disconnected():
	UiToast.ShowToast("Server disconnected")
	_on_back_pressed()


func _on_client_connection_failed(reason: String):
	# Free ride falls back to solo instead (set_single_or_multiplayer_ui)
	if return_ctx.mode == LobbyStateContext.Mode.FREEROAM:
		return
	UiToast.ShowToast("Connection failed: %s" % reason, UiToast.ToastLevel.ERR)
	_on_back_pressed()


func _on_client_connection_succeeded(peer_id: int):
	DebugUtils.auto_join = false
	loading_ui.hide()
	timeout_timer.stop()
	if !multiplayer.is_server():
		level_select_panel.set_controls_disabled(true)

	var player_def = save_manager.get_player_definition()
	lobby_manager.update_player_metadata.rpc_id(1, peer_id, player_def.to_dict())


func _on_timeout():
	UiToast.ShowToast("Connection timed out", UiToast.ToastLevel.ERR)
	_on_back_pressed()


## --autohost starts once the --autojoin peer is in
func _on_lobby_players_updated(players: Dictionary):
	if DebugUtils.auto_host and players.size() == AUTO_HOST_LOBBY_SIZE:
		DebugUtils.auto_host = false
		_on_start_pressed()


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

	# Re-entering with a live connection (e.g. back from customize) — starting the server
	# again would replace multiplayer_peer and drop every connected client, and the join
	# timeout would tear the session down. Reuse the existing connection instead.
	var already_connected: bool = (
		multiplayer.multiplayer_peer != null
		and multiplayer.multiplayer_peer is not OfflineMultiplayerPeer
	)

	match return_ctx.mode:
		LobbyStateContext.Mode.FREEROAM:
			multiplayer_ui.hide()
			singleplayer_ui.show()
			if not already_connected:
				# The offline peer reports is_server() too — starting now runs the match with no lobby player
				level_select_panel.set_controls_disabled(true)
				# Friends late-join; free ride must still work offline, so fall back to a local server
				var err: Error = await connection_manager.start_server()
				# Not after Back mid-host: that would leave a server running behind the play menu
				if err != OK and menu_manager.state_machine.current_state == self:
					UiToast.ShowToast("Couldn't go online, riding solo", UiToast.ToastLevel.WARN)
					connection_manager.connection_mode = ConnectionManager.ConnectionMode.WEBRTC
					await connection_manager.start_server(true)
				level_select_panel.set_controls_disabled(false)
			level_select_panel.grab_start_focus()
		_:
			singleplayer_ui.hide()
			multiplayer_ui.show()
			if already_connected:
				if !multiplayer.is_server():
					level_select_panel.set_controls_disabled(true)
			else:
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
	if steam_manager == null:
		issues.append("steam_manager must not be empty")
	if customize_menu_state == null:
		issues.append("customize_menu_state must not be empty")
	if play_menu_state == null:
		issues.append("play_menu_state must not be empty")

	return issues
