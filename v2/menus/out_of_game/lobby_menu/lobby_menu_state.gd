@tool
class_name LobbyMenuState extends MenuState

@export var menu_manager: MenuManager
@export var multiplayer_manager: MultiplayerManager
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

	set_single_or_multiplayer_ui()
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


## Hide or Show the singleplayer / multiplayer ui depending on ctx.mode
func set_single_or_multiplayer_ui():
	match ctx.mode:
		LobbyStateContext.Mode.FREEROAM:
			multiplayer_ui.hide()
			singleplayer_ui.show()
		_:
			singleplayer_ui.hide()
			multiplayer_ui.show()


## Add ID as a player_list_item_scene to the player_list
func add_player_to_lobby(id: int):
	# TODO: get PlayerDefinition from server... somehow
	var player_li = player_list_item_scene.instantiate() as PlayerListItem
	player_li.player_definition.username = str(id)
	player_li.update_ui_from_player_definition()

	player_list.add_child(player_li)


#region button handlers
func _on_level_selected(idx: int):
	if idx == 0:
		return

	# TODO: Check w/ Multiplayer authority
	start_btn.disabled = false


func _on_start_pressed():
	level_manager.spawn_level(level_select_btn.selected, InputManager.InputState.IN_GAME)
	multiplayer_manager.spawn_players()


func _on_back_pressed():
	transitioned.emit(play_menu_state, null)


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
	if level_manager == null:
		issues.append("level_manager must not be empty")
	if input_manager == null:
		issues.append("input_manager must not be empty")
	if play_menu_state == null:
		issues.append("play_menu_state must not be empty")

	return issues
