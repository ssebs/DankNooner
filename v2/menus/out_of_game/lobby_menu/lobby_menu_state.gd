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

	# Multiplayer :D
	multiplayer_manager.player_connected.connect(_on_player_connected)
	multiplayer_manager.player_disconnected.connect(_on_player_disconnected)

	set_single_or_multiplayer_ui()
	set_levels_in_dropdown(2)


func Exit(_state_context: StateContext):
	ui.hide()
	ctx = null
	back_btn.pressed.disconnect(_on_back_pressed)
	start_btn.pressed.disconnect(_on_start_pressed)
	level_select_btn.item_selected.disconnect(_on_level_selected)

	multiplayer_manager.player_connected.disconnect(_on_player_connected)
	multiplayer_manager.player_disconnected.disconnect(_on_player_disconnected)


#region multiplayer


func _on_player_connected(_id: int, all_players: Array[int]):
	if multiplayer.is_server():
		set_lobby_players.rpc(all_players)


func _on_player_disconnected(id: int):
	rm_lobby_player.rpc(str(id))


func TODO(test: bool):
	pass
	# # Reset stuff when the server disconnects you
	# multiplayer_manager.server_disconnected.connect(
	# 	func():
	# 		if level != null:
	# 			level.queue_free()
	# 		lobby_ui.show()
	# 		lobby_ui.clear_lobby_players()
	# 		text_chat_ui.clear_chat()
	# )


## Add username as a player_list_item_scene to the player_list
func add_player_listitem_to_lobby(username: String):
	# TODO: get PlayerDefinition from server... somehow
	var player_li = player_list_item_scene.instantiate() as PlayerListItem
	player_li.player_definition.username = str(username)
	player_list.add_child(player_li)
	player_li.name = username
	player_li.update_ui_from_player_definition()


## Remove username from player_list. e.g. to show they disconnected
func rm_player_listitem_from_lobby(username: String):
	for child in player_list.get_children():
		if child.name == username:
			child.queue_free()


@rpc("call_local", "reliable")
func set_lobby_players(player_names: Array[int]):
	for player_id in player_names:
		var player_name = str(player_id)
		if player_list.has_node(player_name):
			continue

		add_player_listitem_to_lobby(player_name)


@rpc("call_local", "reliable")
func rm_lobby_player(username: String):
	rm_player_listitem_from_lobby(username)


@rpc("call_local", "reliable")
func start_game():
	level_manager.spawn_level(level_select_btn.selected, InputManager.InputState.IN_GAME)
	multiplayer_manager.spawn_players()


func clear_lobby_players():
	for child in player_list.get_children():
		child.queue_free()


#endregion


## Generate level select items from level_manager
func set_levels_in_dropdown(default_id: int):
	var items = level_manager.get_levels_as_option_items()

	level_select_btn.clear()

	for level_name_str in items:
		level_select_btn.add_item(level_name_str, items[level_name_str])

	level_select_btn.set_item_disabled(0, true)  # Always set to LEVEL_SELECT_LABEL

	# set default
	level_select_btn.selected = default_id
	_on_level_selected(default_id)


## Hide or Show the singleplayer / multiplayer ui depending on ctx.mode
func set_single_or_multiplayer_ui():
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

	if multiplayer.is_server():
		start_btn.disabled = false
		share_with_clients.rpc(idx)


@rpc("reliable")
func share_with_clients(idx: int):
	level_select_btn.selected = idx


func _on_start_pressed():
	if multiplayer.is_server():
		start_game.rpc()


func _on_back_pressed():
	# Disconnect based on whether we're host or client
	if multiplayer.is_server():
		multiplayer_manager.stop_server()  # you'd need to add this
	else:
		multiplayer_manager.disconnect_client()

	clear_lobby_players()

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
