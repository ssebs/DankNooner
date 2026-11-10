@tool
class_name PlayMenuState extends MenuState

@export var menu_manager: MenuManager
@export var connection_manager: ConnectionManager
@export var steam_manager: SteamManager
@export var save_manager: SaveManager
@export var main_menu_state: MenuState
@export var lobby_menu_state: MenuState
@export var customize_menu_state: MenuState
@export var server_browser_menu_state: MenuState

const NORAY_OID_LENGTH := 21
const NORAY_OID_CHARSET := "useandom-26T198340PX75pxJACKVERYMINDBUSHWOLF_GQZbfghjklqvwyzrict"

const WEBRTC_CODE_LENGTH := 32
const WEBRTC_CODE_CHARSET := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"

# Lobby-type Steam IDs always have 18 digits
const STEAM_LOBBY_ID_LENGTH := 18

const AUTO_JOIN_ADDR := "127.0.0.1"

@onready var back_btn: Button = %BackBtn
@onready var customize_btn: Button = %CustomizeBtn
@onready var tutorials_section: Control = %Tutorials
@onready var tutorial_btn: Button = %TutorialBtn
@onready var advanced_tutorial_btn: Button = %AdvancedTutorialBtn
@onready var free_roam_btn: Button = %FreeRoamBtn
@onready var host_btn: Button = %HostBtn
@onready var join_btn: Button = %JoinBtn
@onready var paste_btn: Button = %PasteBtn
@onready var code_entry: LineEdit = %CodeEntry
@onready var host_mode_opt: OptionButton = %HostModeOpt
@onready var server_browser_btn: Button = %ServerBrowserBtn


func Enter(_state_context: StateContext):
	ui.show()

	back_btn.pressed.connect(_on_back_pressed)
	customize_btn.pressed.connect(_on_customize_pressed)
	tutorial_btn.pressed.connect(_on_tutorial_btn_pressed)
	advanced_tutorial_btn.pressed.connect(_on_advanced_tutorial_btn_pressed)
	free_roam_btn.pressed.connect(_on_free_roam_btn_pressed)
	host_btn.pressed.connect(_on_host_btn_pressed)
	join_btn.pressed.connect(_on_join_btn_pressed)
	paste_btn.pressed.connect(_on_paste_btn_pressed)
	code_entry.text_changed.connect(_on_code_text_changed)
	server_browser_btn.pressed.connect(_on_server_browser_pressed)
	steam_manager.invite_received.connect(_on_invite_received)

	server_browser_btn.visible = steam_manager.is_logged_in()

	# Raw keys: OptionButton auto-translates. First item is the default
	host_mode_opt.clear()
	if steam_manager.is_logged_in():
		host_mode_opt.add_item("USE_STEAM_LABEL", ConnectionManager.ConnectionMode.STEAM)
	host_mode_opt.add_item("USE_WEBRTC_LABEL", ConnectionManager.ConnectionMode.WEBRTC)
	host_mode_opt.add_item("USE_IPPORT_LABEL", ConnectionManager.ConnectionMode.IP_PORT)
	host_mode_opt.select(0)
	_update_placeholder()

	# Everything but the main tutorial (Advanced too) stays locked until it's been finished once.
	var locked := !save_manager.is_tutorial_complete()
	# On top (so MenuManager focuses it) until the tutorial's done, then last.
	tutorials_section.get_parent().move_child(tutorials_section, 0 if locked else -1)
	for control: BaseButton in [
		customize_btn, free_roam_btn, host_btn, paste_btn, host_mode_opt, server_browser_btn,
		advanced_tutorial_btn
	]:
		control.disabled = locked
	code_entry.editable = !locked
	if locked:
		join_btn.disabled = true
	else:
		_validate_code(code_entry.text)

	if !steam_manager.pending_game_id.is_empty():
		_on_invite_received.call_deferred()
	elif DebugUtils.auto_host:
		host_mode_opt.select(
			host_mode_opt.get_item_index(ConnectionManager.ConnectionMode.IP_PORT)
		)
		_on_host_btn_pressed.call_deferred()
	elif DebugUtils.auto_join:
		# A failed join lands back here and retries, so racing the host's boot is fine
		join_game.call_deferred(AUTO_JOIN_ADDR)


func Exit(_state_context: StateContext):
	ui.hide()
	back_btn.pressed.disconnect(_on_back_pressed)
	customize_btn.pressed.disconnect(_on_customize_pressed)
	tutorial_btn.pressed.disconnect(_on_tutorial_btn_pressed)
	advanced_tutorial_btn.pressed.disconnect(_on_advanced_tutorial_btn_pressed)
	free_roam_btn.pressed.disconnect(_on_free_roam_btn_pressed)
	host_btn.pressed.disconnect(_on_host_btn_pressed)
	join_btn.pressed.disconnect(_on_join_btn_pressed)
	paste_btn.pressed.disconnect(_on_paste_btn_pressed)
	code_entry.text_changed.disconnect(_on_code_text_changed)
	server_browser_btn.pressed.disconnect(_on_server_browser_pressed)
	steam_manager.invite_received.disconnect(_on_invite_received)


func _on_paste_btn_pressed():
	code_entry.text = DisplayServer.clipboard_get()
	_on_code_text_changed(code_entry.text)


func _on_code_text_changed(new_text: String):
	var text := new_text.strip_edges()

	_auto_detect_connection_mode(text)
	_validate_code(text)


func _auto_detect_connection_mode(text: String):
	if text.is_empty():
		return

	if text.is_valid_ip_address():
		connection_manager.connection_mode = ConnectionManager.ConnectionMode.IP_PORT
	elif _is_valid_noray_oid(text):
		connection_manager.connection_mode = ConnectionManager.ConnectionMode.NORAY
	elif _is_valid_webrtc_id(text):
		connection_manager.connection_mode = ConnectionManager.ConnectionMode.WEBRTC
	elif _is_valid_steam_lobby_id(text):
		connection_manager.connection_mode = ConnectionManager.ConnectionMode.STEAM


func _update_placeholder():
	code_entry.placeholder_text = tr("GAME_CODE_PLACEHOLDER")


func _validate_code(text: String):
	join_btn.disabled = not (
		text.is_valid_ip_address()
		or _is_valid_noray_oid(text)
		or _is_valid_webrtc_id(text)
		or _is_valid_steam_lobby_id(text)
	)


func _is_valid_webrtc_id(text: String) -> bool:
	var trimmed := text.strip_edges()
	if trimmed.length() != WEBRTC_CODE_LENGTH:
		return false
	for c in trimmed:
		if c not in WEBRTC_CODE_CHARSET:
			return false
	return true


## Joining a Steam lobby needs Steam
func _is_valid_steam_lobby_id(text: String) -> bool:
	var trimmed := text.strip_edges()
	return (
		steam_manager.is_logged_in()
		and trimmed.length() == STEAM_LOBBY_ID_LENGTH
		and trimmed.is_valid_int()
	)


func _is_valid_noray_oid(text: String) -> bool:
	var trimmed := text.strip_edges()
	if trimmed.length() != NORAY_OID_LENGTH:
		return false
	for c in trimmed:
		if c not in NORAY_OID_CHARSET:
			return false
	return true


#region button handlers
func _on_host_btn_pressed():
	connection_manager.connection_mode = (
		host_mode_opt.get_selected_id() as ConnectionManager.ConnectionMode
	)
	transitioned.emit(lobby_menu_state, LobbyStateContext.NewHost(self, "0.0.0.0"))
	await connection_manager.start_server()


func _on_join_btn_pressed():
	join_game(code_entry.text.strip_edges())


func _on_invite_received():
	if !save_manager.is_tutorial_complete():
		steam_manager.pending_game_id = ""
		UiToast.ShowToast(tr("TOAST_FINISH_TUTORIAL_FIRST"))
		return
	join_game(steam_manager.take_pending_game_id())


## Also the server browser's join, with itself as the lobby's Back target
func join_game(game_id: String, back_to: MenuState = self):
	_auto_detect_connection_mode(game_id)
	var ctx = LobbyStateContext.NewJoin(back_to, game_id)
	transitioned.emit(lobby_menu_state, ctx)  # must be before connecting client for ip to show

	var err = await connection_manager.connect_client(game_id)
	if err != OK:
		UiToast.ShowToast(tr("TOAST_FAILED_TO_CONNECT"), UiToast.ToastLevel.ERR, 3)
		return


func _on_free_roam_btn_pressed():
	# Host on the default transport, not the selected one
	connection_manager.connection_mode = (
		host_mode_opt.get_item_id(0) as ConnectionManager.ConnectionMode
	)
	transitioned.emit(lobby_menu_state, LobbyStateContext.NewFreeRoam(self))


func _on_tutorial_btn_pressed():
	transitioned.emit(lobby_menu_state, LobbyStateContext.NewStory(self))


func _on_advanced_tutorial_btn_pressed():
	transitioned.emit(lobby_menu_state, LobbyStateContext.NewStory(self, TutorialGameMode.ADVANCED_EVENT_NAME))


func _on_customize_pressed():
	transitioned.emit(customize_menu_state, StateContext.NewWithReturn(self))


func _on_server_browser_pressed():
	transitioned.emit(server_browser_menu_state, StateContext.NewWithReturn(self))


func _on_back_pressed():
	transitioned.emit(main_menu_state, StateContext.NewWithReturn(self))


#endregion


#override
func on_cancel_key_pressed():
	_on_back_pressed()


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if menu_manager == null:
		issues.append("menu_manager must not be empty")
	if connection_manager == null:
		issues.append("connection_manager must not be empty")
	if steam_manager == null:
		issues.append("steam_manager must not be empty")
	if save_manager == null:
		issues.append("save_manager must not be empty")
	if main_menu_state == null:
		issues.append("main_menu_state must not be empty")
	if lobby_menu_state == null:
		issues.append("lobby_menu_state must not be empty")
	if customize_menu_state == null:
		issues.append("customize_menu_state must not be empty")
	if server_browser_menu_state == null:
		issues.append("server_browser_menu_state must not be empty")

	return issues
