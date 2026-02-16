@tool
class_name LobbyMenuState extends MenuState

@export var menu_manager: MenuManager
@export var settings_manager: SettingsManager
@export var multiplayer_manager: MultiplayerManager
@export var level_manager: LevelManager
@export var input_state_manager: InputStateManager

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
# @onready var invite_btn: Button = %InviteBtn
@onready var player_list: VBoxContainer = %PlayersList
@onready var loading_ui: ColorRect = %LoadingUI
@onready var timeout_timer: Timer = %TimeoutTimer

var ctx: LobbyStateContext


func Enter(state_context: StateContext):
	if state_context is not LobbyStateContext:
		printerr("Must pass LobbyStateContext type when transitioning to LobbyMenuState")
		return

	ctx = state_context
	ui.show()
	loading_ui.hide()

	back_btn.pressed.connect(_on_back_pressed)
	start_btn.pressed.connect(_on_start_pressed)
	level_select_btn.item_selected.connect(_on_level_selected)
	ip_copy_btn.pressed.connect(_on_ip_copy_btn_pressed)

	# Multiplayer :D
	multiplayer_manager.player_connected.connect(_on_player_connected)
	multiplayer_manager.player_disconnected.connect(_on_player_disconnected)
	multiplayer_manager.server_disconnected.connect(_on_server_disconnected)
	multiplayer_manager.game_id_set.connect(_on_game_id_set)
	multiplayer_manager.client_connection_failed.connect(_on_client_connection_failed)
	multiplayer_manager.client_connection_succeeded.connect(_on_client_connection_succeeded)
	multiplayer_manager.lobby_players_updated.connect(_on_lobby_players_updated)

	timeout_timer.timeout.connect(_on_timeout)

	set_single_or_multiplayer_ui()
	set_levels_in_dropdown(1)


func Exit(_state_context: StateContext):
	ui.hide()
	ctx = null
	clear_lobby_players()

	back_btn.pressed.disconnect(_on_back_pressed)
	start_btn.pressed.disconnect(_on_start_pressed)
	level_select_btn.item_selected.disconnect(_on_level_selected)
	ip_copy_btn.pressed.disconnect(_on_ip_copy_btn_pressed)

	multiplayer_manager.player_connected.disconnect(_on_player_connected)
	multiplayer_manager.player_disconnected.disconnect(_on_player_disconnected)
	multiplayer_manager.server_disconnected.disconnect(_on_server_disconnected)
	multiplayer_manager.game_id_set.disconnect(_on_game_id_set)
	multiplayer_manager.client_connection_failed.disconnect(_on_client_connection_failed)
	multiplayer_manager.client_connection_succeeded.disconnect(_on_client_connection_succeeded)
	multiplayer_manager.lobby_players_updated.disconnect(_on_lobby_players_updated)

	timeout_timer.timeout.disconnect(_on_timeout)
	timeout_timer.stop()


#region multiplayer
func _on_game_id_set(conn_addr: String):
	print("conn_addr: %s" % conn_addr)
	ip_label.text = conn_addr
	ip_copy_btn.disabled = false
	if multiplayer.multiplayer_peer && multiplayer.is_server():
		_on_ip_copy_btn_pressed()


func _on_player_connected(_id: int, _all_players: Dictionary):
	# Server will broadcast updated lobby_players via sync_lobby_players after username is set
	pass


func _on_player_disconnected(_id: int):
	# Server will broadcast updated lobby_players via sync_lobby_players
	pass


func _on_lobby_players_updated(players: Dictionary):
	loading_ui.hide()
	timeout_timer.stop()

	# Remove players no longer in the dict
	for child in player_list.get_children():
		var child_id = int(child.name)
		if !players.has(child_id):
			child.queue_free()

	# Add or update players
	for player_id in players:
		var username: String = players[player_id]
		var node_name = str(player_id)

		if player_list.has_node(node_name):
			# Update existing player's username
			var player_li = player_list.get_node(node_name) as PlayerListItem
			player_li.player_definition.username = username
			player_li.update_ui_from_player_definition()
		else:
			# Add new player
			add_player_listitem_to_lobby(player_id, username)


func _on_server_disconnected():
	print("_on_server_disconnected")

	_on_back_pressed()


func _on_client_connection_failed(reason: String):
	UiToast.ShowToast("Connection failed: %s" % reason, UiToast.ToastLevel.ERR)
	_on_back_pressed()


func _on_client_connection_succeeded():
	# Wait for ENet to actually connect before sending RPCs
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		multiplayer.connected_to_server.connect(_on_enet_connected, CONNECT_ONE_SHOT)
	else:
		_on_enet_connected()


func _on_enet_connected():
	loading_ui.hide()
	timeout_timer.stop()
	if !multiplayer.is_server():
		start_btn.disabled = true

	multiplayer_manager.update_username.rpc_id(
		1, multiplayer.get_unique_id(), settings_manager.current_settings["username"]
	)


func _on_timeout():
	UiToast.ShowToast("Connection timed out", UiToast.ToastLevel.ERR)
	_on_back_pressed()


@rpc("call_local", "reliable")
func start_game():
	# Get level name from selected
	var level_name = level_select_btn.get_item_id(level_select_btn.selected)

	level_manager.spawn_level(level_name, InputStateManager.InputState.IN_GAME)
	level_manager.spawn_players()


@rpc("call_local", "reliable")
func share_selected_level_with_clients(idx: int):
	level_select_btn.selected = idx


#endregion


#region button handlers
func _on_level_selected(idx: int):
	if idx == 0:
		return

	if multiplayer.multiplayer_peer && multiplayer.is_server():
		start_btn.disabled = false
		share_selected_level_with_clients.rpc(idx)


func _on_start_pressed():
	if multiplayer.multiplayer_peer && multiplayer.is_server():
		start_game.rpc()


## cleanup before going back
func _on_back_pressed():
	multiplayer_manager.disconnect_sp_or_mp()

	clear_lobby_players()
	if level_manager.current_level_name != LevelManager.LevelName.BG_GRAY_LEVEL:
		level_manager.spawn_menu_level()

	transitioned.emit(play_menu_state, null)


func _on_ip_copy_btn_pressed():
	DisplayServer.clipboard_set(ip_label.text)
	UiToast.ShowToast("GameID copied to clipboard!")


#endregion
#region UI helpers
## Add player to player_list UI
func add_player_listitem_to_lobby(player_id: int, username: String):
	var player_li = player_list_item_scene.instantiate() as PlayerListItem
	player_li.player_definition.username = username
	player_list.add_child(player_li)
	player_li.name = str(player_id)

	if player_id == 1:
		player_li.host_label.text = "PLAYER_IS_HOST_LABEL"
	elif player_id == multiplayer.get_unique_id():
		player_li.host_label.text = "YOU_LABEL"
	else:
		player_li.host_label.text = ""

	player_li.update_ui_from_player_definition()


## Empty player_list
func clear_lobby_players():
	for child in player_list.get_children():
		child.queue_free()


## Generate level select items from level_manager
func set_levels_in_dropdown(default_id: int):
	var items = level_manager.get_levels_as_option_items()

	level_select_btn.clear()

	for level_name_str in items:
		level_select_btn.add_item(level_name_str, items[level_name_str])

	level_select_btn.set_item_disabled(0, true)  # Always set to LEVEL_SELECT_LABEL

	# set default
	level_select_btn.selected = default_id


## Hide or Show the singleplayer / multiplayer ui depending on ctx.mode
func set_single_or_multiplayer_ui():
	match ctx.mode:
		LobbyStateContext.Mode.FREEROAM:
			multiplayer_ui.hide()
			singleplayer_ui.show()
			await multiplayer_manager.start_server()
		_:
			singleplayer_ui.hide()
			multiplayer_ui.show()
			loading_ui.show()
			timeout_timer.start()
			start_btn.disabled = false


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
	if input_state_manager == null:
		issues.append("input_state_manager must not be empty")
	if settings_manager == null:
		issues.append("settings_manager must not be empty")
	if play_menu_state == null:
		issues.append("play_menu_state must not be empty")

	return issues
