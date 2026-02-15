@tool
class_name PlayMenuState extends MenuState

@export var menu_manager: MenuManager
@export var multiplayer_manager: MultiplayerManager
@export var main_menu_state: MenuState
@export var lobby_menu_state: MenuState
@export var customize_menu_state: MenuState

const NORAY_OID_LENGTH := 21
const NORAY_OID_CHARSET := "useandom-26T198340PX75pxJACKVERYMINDBUSHWOLF_GQZbfghjklqvwyzrict"

@onready var back_btn: Button = %BackBtn
@onready var customize_btn: Button = %CustomizeBtn
@onready var free_roam_btn: Button = %FreeRoamBtn
# @onready var story_btn: Button = %StoryBtn
@onready var host_btn: Button = %HostBtn
@onready var join_btn: Button = %JoinBtn
@onready var paste_btn: Button = %PasteBtn
@onready var code_entry: LineEdit = %CodeEntry


func Enter(_state_context: StateContext):
	ui.show()

	back_btn.pressed.connect(_on_back_pressed)
	customize_btn.pressed.connect(_on_customize_pressed)
	free_roam_btn.pressed.connect(_on_free_roam_btn_pressed)
	host_btn.pressed.connect(_on_host_btn_pressed)
	join_btn.pressed.connect(_on_join_btn_pressed)
	paste_btn.pressed.connect(_on_paste_btn_pressed)
	code_entry.text_changed.connect(_on_code_text_changed)

	_validate_code()


func Exit(_state_context: StateContext):
	ui.hide()
	back_btn.pressed.disconnect(_on_back_pressed)
	customize_btn.pressed.disconnect(_on_customize_pressed)
	free_roam_btn.pressed.disconnect(_on_free_roam_btn_pressed)
	host_btn.pressed.disconnect(_on_host_btn_pressed)
	join_btn.pressed.disconnect(_on_join_btn_pressed)
	paste_btn.pressed.disconnect(_on_paste_btn_pressed)
	code_entry.text_changed.disconnect(_on_code_text_changed)


func _on_paste_btn_pressed():
	code_entry.text = DisplayServer.clipboard_get()
	_validate_code()


func _on_code_text_changed(_new_text: String):
	_validate_code()


func _validate_code():
	join_btn.disabled = not _is_valid_noray_oid(code_entry.text)


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
	# UiToast.ShowToast("Hosting game!", UiToast.ToastLevel.NORMAL, 5)
	transitioned.emit(lobby_menu_state, LobbyStateContext.NewHost("0.0.0.0"))
	multiplayer_manager.start_server()


func _on_join_btn_pressed():
	var oid := code_entry.text.strip_edges()
	var err = await multiplayer_manager.connect_client(oid)
	if err != OK:
		UiToast.ShowToast("Failed to connect to server", UiToast.ToastLevel.ERR, 3)
		return
	var ctx = LobbyStateContext.NewJoin(oid)
	transitioned.emit(lobby_menu_state, ctx)


func _on_free_roam_btn_pressed():
	transitioned.emit(lobby_menu_state, LobbyStateContext.NewFreeRoam())


func _on_customize_pressed():
	transitioned.emit(customize_menu_state, null)


func _on_back_pressed():
	transitioned.emit(main_menu_state, null)


#endregion


#override
func on_cancel_key_pressed():
	_on_back_pressed()


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if menu_manager == null:
		issues.append("menu_manager must not be empty")
	if multiplayer_manager == null:
		issues.append("multiplayer_manager must not be empty")
	if main_menu_state == null:
		issues.append("main_menu_state must not be empty")
	if lobby_menu_state == null:
		issues.append("lobby_menu_state must not be empty")
	if customize_menu_state == null:
		issues.append("customize_menu_state must not be empty")

	return issues
