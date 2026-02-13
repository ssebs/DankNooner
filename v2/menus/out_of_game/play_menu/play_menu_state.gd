@tool
class_name PlayMenuState extends MenuState

@export var menu_manager: MenuManager
@export var multiplayer_manager: MultiplayerManager
@export var main_menu_state: MenuState
@export var lobby_menu_state: MenuState
@export var customize_menu_state: MenuState

@onready var back_btn: Button = %BackBtn
@onready var customize_btn: Button = %CustomizeBtn
@onready var free_roam_btn: Button = %FreeRoamBtn
# @onready var story_btn: Button = %StoryBtn
@onready var host_btn: Button = %HostBtn
@onready var join_btn: Button = %JoinBtn

@onready var ip_entry: LineEdit = %IPEntry


func Enter(_state_context: StateContext):
	ui.show()

	back_btn.pressed.connect(_on_back_pressed)
	customize_btn.pressed.connect(_on_customize_pressed)
	free_roam_btn.pressed.connect(_on_free_roam_btn_pressed)
	host_btn.pressed.connect(_on_host_btn_pressed)
	join_btn.pressed.connect(_on_join_btn_pressed)

	ip_entry.text_changed.connect(_on_ip_text_changed)
	# Default text is 127.0.0.1
	join_btn.disabled = false


func Exit(_state_context: StateContext):
	ui.hide()
	back_btn.pressed.disconnect(_on_back_pressed)
	customize_btn.pressed.disconnect(_on_customize_pressed)
	free_roam_btn.pressed.disconnect(_on_free_roam_btn_pressed)
	host_btn.pressed.disconnect(_on_host_btn_pressed)
	join_btn.pressed.disconnect(_on_join_btn_pressed)

	ip_entry.text_changed.disconnect(_on_ip_text_changed)


func _on_ip_text_changed(_new_text: String):
	# TODO: validate oid
	if join_btn.disabled:
		join_btn.disabled = false
	# if new_text.is_valid_ip_address():
	# 	join_btn.disabled = false
	# else:
	# 	join_btn.disabled = true


#region button handlers
func _on_host_btn_pressed():
	# UiToast.ShowToast("Hosting game!", UiToast.ToastLevel.NORMAL, 5)
	transitioned.emit(lobby_menu_state, LobbyStateContext.NewHost("0.0.0.0"))
	multiplayer_manager.start_server()


func _on_join_btn_pressed():
	var ctx = LobbyStateContext.NewJoin(ip_entry.text)
	multiplayer_manager.connect_client(ip_entry.text)
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
