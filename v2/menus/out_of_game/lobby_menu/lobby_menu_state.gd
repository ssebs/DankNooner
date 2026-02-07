@tool
class_name LobbyMenuState extends MenuState

@export var menu_manager: MenuManager
@export var level_manager: LevelManager
@export var input_manager: InputManager

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
# @onready var ip_copy_btn: Button = %IPCopyBtn
# @onready var invite_btn: Button = %InviteBtn
@onready var player_list: VBoxContainer = %PlayersList

var ctx: LobbyStateContext


func Enter(state_context: StateContext):
	if state_context is not LobbyStateContext:
		printerr("Must pass LobbyStateContext type when transitioning to LobbyMenuState")
		return

	ctx = state_context
	ui.show()

	back_btn.pressed.connect(_on_back_pressed)
	start_btn.pressed.connect(_on_start_pressed)
	level_select_btn.item_selected.connect(_on_level_selected)

	start_btn.disabled = true  # enable when level is selected

	set_panel_rename_me()
	set_levels_in_dropdown()


func Exit(_state_context: StateContext):
	ui.hide()
	ctx = null
	back_btn.pressed.disconnect(_on_back_pressed)
	start_btn.pressed.disconnect(_on_start_pressed)
	level_select_btn.item_selected.disconnect(_on_level_selected)


## Generate level select items from level_manager
func set_levels_in_dropdown():
	var items = level_manager.get_levels_as_option_items()

	level_select_btn.clear()

	for level_name_str in items:
		level_select_btn.add_item(level_name_str, items[level_name_str])

	level_select_btn.set_item_disabled(0, true)  # Always set to LEVEL_SELECT_LABEL


func set_panel_rename_me():
	match ctx.mode:
		LobbyStateContext.Mode.FREEROAM:
			multiplayer_ui.hide()
			singleplayer_ui.show()
		_:
			singleplayer_ui.hide()
			multiplayer_ui.show()


#region button handlers
func _on_level_selected(idx: int):
	if idx == 0:
		return

	# TODO: Check w/ Multiplayer authority
	start_btn.disabled = false


func _on_start_pressed():
	level_manager.spawn_level(level_select_btn.selected, InputManager.InputState.IN_GAME)


func _on_back_pressed():
	transitioned.emit(play_menu_state, null)


#endregion


#override
func on_cancel_key_pressed():
	_on_back_pressed()
