@tool
class_name PlayMenuState extends MenuState

@export var menu_manager: MenuManager
@export var connection_manager: ConnectionManager
@export var steam_manager: SteamManager
@export var main_menu_state: MenuState
@export var lobby_menu_state: MenuState
@export var customize_menu_state: MenuState

const NORAY_OID_LENGTH := 21
const NORAY_OID_CHARSET := "useandom-26T198340PX75pxJACKVERYMINDBUSHWOLF_GQZbfghjklqvwyzrict"

const WEBRTC_CODE_LENGTH := 32
const WEBRTC_CODE_CHARSET := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"

# Lobby-type Steam IDs always have 18 digits
const STEAM_LOBBY_ID_LENGTH := 18

@onready var back_btn: Button = %BackBtn
@onready var customize_btn: Button = %CustomizeBtn
@onready var free_roam_btn: Button = %FreeRoamBtn
# @onready var story_btn: Button = %StoryBtn
@onready var host_btn: Button = %HostBtn
@onready var join_btn: Button = %JoinBtn
@onready var paste_btn: Button = %PasteBtn
@onready var code_entry: LineEdit = %CodeEntry
@onready var host_mode_opt: OptionButton = %HostModeOpt


func Enter(_state_context: StateContext):
	ui.show()

	back_btn.pressed.connect(_on_back_pressed)
	customize_btn.pressed.connect(_on_customize_pressed)
	free_roam_btn.pressed.connect(_on_free_roam_btn_pressed)
	host_btn.pressed.connect(_on_host_btn_pressed)
	join_btn.pressed.connect(_on_join_btn_pressed)
	paste_btn.pressed.connect(_on_paste_btn_pressed)
	code_entry.text_changed.connect(_on_code_text_changed)
	steam_manager.invite_received.connect(_on_invite_received)

	# Raw keys: OptionButton auto-translates. First item is the default
	host_mode_opt.clear()
	if steam_manager.is_logged_in():
		host_mode_opt.add_item("USE_STEAM_LABEL", ConnectionManager.ConnectionMode.STEAM)
	host_mode_opt.add_item("USE_WEBRTC_LABEL", ConnectionManager.ConnectionMode.WEBRTC)
	host_mode_opt.add_item("USE_IPPORT_LABEL", ConnectionManager.ConnectionMode.IP_PORT)
	host_mode_opt.select(0)
	_update_placeholder()

	if !steam_manager.pending_game_id.is_empty():
		_on_invite_received.call_deferred()


func Exit(_state_context: StateContext):
	ui.hide()
	back_btn.pressed.disconnect(_on_back_pressed)
	customize_btn.pressed.disconnect(_on_customize_pressed)
	free_roam_btn.pressed.disconnect(_on_free_roam_btn_pressed)
	host_btn.pressed.disconnect(_on_host_btn_pressed)
	join_btn.pressed.disconnect(_on_join_btn_pressed)
	paste_btn.pressed.disconnect(_on_paste_btn_pressed)
	code_entry.text_changed.disconnect(_on_code_text_changed)
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
	_join_game(code_entry.text.strip_edges())


func _on_invite_received():
	_join_game(steam_manager.take_pending_game_id())


func _join_game(game_id: String):
	_auto_detect_connection_mode(game_id)
	var ctx = LobbyStateContext.NewJoin(self, game_id)
	transitioned.emit(lobby_menu_state, ctx)  # must be before connecting client for ip to show

	var err = await connection_manager.connect_client(game_id)
	if err != OK:
		UiToast.ShowToast("Failed to connect to server", UiToast.ToastLevel.ERR, 3)
		return


func _on_free_roam_btn_pressed():
	transitioned.emit(lobby_menu_state, LobbyStateContext.NewFreeRoam(self))


func _on_customize_pressed():
	transitioned.emit(customize_menu_state, StateContext.NewWithReturn(self))


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
	if main_menu_state == null:
		issues.append("main_menu_state must not be empty")
	if lobby_menu_state == null:
		issues.append("lobby_menu_state must not be empty")
	if customize_menu_state == null:
		issues.append("customize_menu_state must not be empty")

	return issues
