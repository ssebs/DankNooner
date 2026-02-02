@tool
class_name LobbyMenuState extends MenuState

# SEE planning_docs\diagrams\play-menu-ui.excalidraw

@export var menu_manager: MenuManager
@export var play_menu_state: MenuState

@export var player_list_item_scene: PackedScene = preload(
	"res://menus/out_of_game/lobby_menu/player_list_item.tscn"
)

@onready var singleplayer_ui: Control = %SingleplayerUI
@onready var multiplayer_ui: Control = %MultiplayerUI

@onready var back_btn: Button = %BackBtn
@onready var level_select_btn: OptionButton = %LevelSelectBtn
@onready var level_preview_tex: TextureRect = %LevelPreview
@onready var start_btn: Button = %StartBtn

@onready var ip_label: Label = %IPLabel
@onready var ip_copy_btn: Button = %IPCopyBtn
@onready var invite_btn: Button = %InviteBtn
@onready var player_list: VBoxContainer = %PlayersList


func Enter(_state_context: StateContext):
	ui.show()
	back_btn.pressed.connect(_on_back_pressed)


func Exit(_state_context: StateContext):
	ui.hide()
	back_btn.pressed.disconnect(_on_back_pressed)


func _on_back_pressed():
	transitioned.emit(play_menu_state, null)
