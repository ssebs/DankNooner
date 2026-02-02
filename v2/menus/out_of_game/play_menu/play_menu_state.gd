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


func Enter():
	ui.show()
	back_btn.pressed.connect(_on_back_pressed)
	customize_btn.pressed.connect(_on_customize_pressed)
	free_roam_btn.pressed.connect(_on_free_roam_btn_pressed)
	host_btn.pressed.connect(_on_host_btn_pressed)
	join_btn.pressed.connect(_on_join_btn_pressed)


func Exit():
	ui.hide()
	back_btn.pressed.disconnect(_on_back_pressed)
	customize_btn.pressed.disconnect(_on_customize_pressed)
	free_roam_btn.pressed.disconnect(_on_free_roam_btn_pressed)
	host_btn.pressed.disconnect(_on_host_btn_pressed)
	join_btn.pressed.disconnect(_on_join_btn_pressed)


func is_ip_valid() -> bool:
	# TODO: implement
	return true


#region button handlers
func _on_host_btn_pressed():
	# TODO: add vars here
	transitioned.emit(lobby_menu_state)


func _on_join_btn_pressed():
	# TODO: make sure ip_entry has an IP
	if !is_ip_valid():
		printerr("IP Address is invalid")  # TODO: add toast
		return
	# TODO: add vars here
	transitioned.emit(lobby_menu_state)


func _on_free_roam_btn_pressed():
	transitioned.emit(lobby_menu_state)


func _on_customize_pressed():
	transitioned.emit(customize_menu_state)


func _on_back_pressed():
	transitioned.emit(main_menu_state)
#endregion
