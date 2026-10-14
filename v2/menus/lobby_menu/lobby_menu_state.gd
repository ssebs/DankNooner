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

@onready var singleplayer_ui: Control = %SingleplayerUI
@onready var multiplayer_ui: Control = %MultiplayerUI

@onready var back_btn: Button = %BackBtn
@onready var level_select_panel: LevelSelectPanel = %LevelSelectPanel
@onready var customize_btn: Button = %CustomizeBtn

@onready var ip_label: Label = %IPLabel
@onready var ip_copy_btn: Button = %IPCopyBtn
@onready var invite_btn: Button = %InviteBtn
@onready var player_list: VBoxContainer = %PlayersList  # PlayerListUI script
@onready var loading_ui: ColorRect = %LoadingUI
@onready var timeout_timer: Timer = %TimeoutTimer
@onready var ping_timer: Timer = %PingTimer


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
	ip_copy_btn.pressed.connect(_on_ip_copy_btn_pressed)
	customize_btn.pressed.connect(_on_customize_pressed)
	invite_btn.pressed.connect(steam_manager.invite_friends)
	steam_manager.avatar_loaded.connect(player_list.set_avatar)

	# Connection signals
	connection_manager.server_disconnected.connect(_on_server_disconnected)
	connection_manager.game_id_set.connect(_on_game_id_set)
	connection_manager.client_connection_failed.connect(_on_client_connection_failed)
	connection_manager.client_connection_succeeded.connect(_on_client_connection_succeeded)

	# Lobby signals
	lobby_manager.lobby_players_updated.connect(_on_lobby_players_updated)

	timeout_timer.timeout.connect(_on_timeout)
	ping_timer.timeout.connect(_on_ping_timer_timeout)
	ping_timer.start()

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
	invite_btn.pressed.disconnect(steam_manager.invite_friends)
	steam_manager.avatar_loaded.disconnect(player_list.set_avatar)

	connection_manager.server_disconnected.disconnect(_on_server_disconnected)
	connection_manager.game_id_set.disconnect(_on_game_id_set)
	connection_manager.client_connection_failed.disconnect(_on_client_connection_failed)
	connection_manager.client_connection_succeeded.disconnect(_on_client_connection_succeeded)

	lobby_manager.lobby_players_updated.disconnect(_on_lobby_players_updated)

	timeout_timer.timeout.disconnect(_on_timeout)
	timeout_timer.stop()
	ping_timer.timeout.disconnect(_on_ping_timer_timeout)
	ping_timer.stop()


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
	# Not the label: joining takes a bare IP, without the port
	DisplayServer.clipboard_set(connection_manager.conn_addr)
	UiToast.ShowToast("Game ID copied to clipboard!")


func _on_customize_pressed():
	# Customize's Back must return HERE (session stays up) — Enter() restores the
	# original back target when it sees return_state == self.
	transitioned.emit(
		customize_menu_state, StateContext.NewWithReturnAndContext(self, return_ctx)
	)


#endregion


#region network signal handlers
## set game join id in ui & enable clipboard btn
func _on_game_id_set(conn_addr: String):
	_show_game_id(conn_addr)
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
	# Each viewer fetches avatars from its own Steam client; without Steam the default icon stays
	if !steam_manager.is_logged_in():
		return
	for player_def: PlayerDefinition in players.values():
		if player_def.steam_id != 0:
			steam_manager.request_avatar(player_def.steam_id)


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


## Only clients measure ping (netfox's time sync RTT to the host)
func _on_ping_timer_timeout():
	if !NetworkTime.is_initial_sync_done() or multiplayer.is_server():
		return
	request_report_ping.rpc_id(1, roundi(NetworkTime.remote_rtt * 1000.0))


#endregion

#region local RPCs
@rpc("call_local", "reliable")
func share_selected_level_with_clients(idx: int):
	level_select_panel.set_selected_index(idx)


## Client → server: the sender reports its own ping
@rpc("any_peer", "call_remote", "unreliable")
func request_report_ping(ping_ms: int):
	if !multiplayer.is_server():
		return
	_sync_ping.rpc(multiplayer.get_remote_sender_id(), ping_ms)


@rpc("call_local", "unreliable")
func _sync_ping(peer_id: int, ping_ms: int):
	if multiplayer.get_remote_sender_id() > 1:
		return
	player_list.set_ping(peer_id, ping_ms)


#endregion


## IP/Port mode adds the port, which the host has to forward
func _show_game_id(conn_addr: String):
	ip_label.text = conn_addr
	# Empty on connection reset
	if (
		!conn_addr.is_empty()
		and connection_manager.connection_mode == ConnectionManager.ConnectionMode.IP_PORT
	):
		ip_label.text += ":%d" % UtilsConstants.PORT


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
				# ENet doesn't work on web — use WebRTC there
				if OS.has_feature("web"):
					connection_manager.connection_mode = ConnectionManager.ConnectionMode.WEBRTC
				else:
					connection_manager.connection_mode = ConnectionManager.ConnectionMode.IP_PORT
				# The offline peer reports is_server() too — starting now runs the match with no lobby player
				level_select_panel.set_controls_disabled(true)
				await connection_manager.start_server(true)
				level_select_panel.set_controls_disabled(false)
			level_select_panel.grab_start_focus()
		_:
			singleplayer_ui.hide()
			multiplayer_ui.show()
			# Only the host owns the Steam lobby friends get invited to
			invite_btn.visible = (
				return_ctx.mode == LobbyStateContext.Mode.HOST and steam_manager.is_logged_in()
			)
			if already_connected:
				_show_game_id(connection_manager.conn_addr)
				ip_copy_btn.disabled = false
				if !multiplayer.is_server():
					level_select_panel.set_controls_disabled(true)
				_on_lobby_players_updated(lobby_manager.lobby_players)
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
