@tool
class_name PlayMenuState extends MenuState

# SEE planning_docs\diagrams\play-menu-ui.excalidraw

@export var menu_manager: MenuManager
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


func Exit(_state_context: StateContext):
	ui.hide()
	back_btn.pressed.disconnect(_on_back_pressed)
	customize_btn.pressed.disconnect(_on_customize_pressed)
	free_roam_btn.pressed.disconnect(_on_free_roam_btn_pressed)
	host_btn.pressed.disconnect(_on_host_btn_pressed)
	join_btn.pressed.disconnect(_on_join_btn_pressed)


func is_ip_valid() -> bool:
	return ip_entry.text.is_valid_ip_address()


#region button handlers
func _on_host_btn_pressed():
	transitioned.emit(lobby_menu_state, LobbyStateContext.NewHost("0.0.0.0"))


func _on_join_btn_pressed():
	if !is_ip_valid():
		printerr("IP Address is invalid")  # TODO: add toast
		return
	var ctx = LobbyStateContext.NewHost(ip_entry.text)
	transitioned.emit(lobby_menu_state, ctx)


func _on_free_roam_btn_pressed():
	transitioned.emit(lobby_menu_state, LobbyStateContext.NewFreeRoam())


func _on_customize_pressed():
	transitioned.emit(customize_menu_state, null)


func _on_back_pressed():
	transitioned.emit(main_menu_state, null)
#endregion
