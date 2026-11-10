@tool
## Friends' Steam lobbies, then public ones, on our version. Joins go through the play menu, with Back
## returning here
class_name ServerBrowserMenuState extends MenuState

@export var steam_manager: SteamManager
@export var level_manager: LevelManager
@export var play_menu_state: PlayMenuState
## Rows are made after MenuState wires click sounds, so they're wired here
@export var audio_manager: AudioManager

@onready var back_btn: Button = %BackBtn
@onready var refresh_btn: Button = %RefreshBtn
@onready var status_label: Label = %StatusLabel
@onready var lobby_list: VBoxContainer = %LobbyList

## Bumped per search and on Exit, so a stale search's results are dropped
var _search_id := 0


func Enter(_state_context: StateContext):
	# Back from a lobby lands here too (its return_state), but Back from here is always the play menu
	return_state = play_menu_state
	ui.show()
	back_btn.pressed.connect(_on_back_pressed)
	refresh_btn.pressed.connect(_on_refresh_pressed)
	_on_refresh_pressed()


func Exit(_state_context: StateContext):
	ui.hide()
	_search_id += 1
	back_btn.pressed.disconnect(_on_back_pressed)
	refresh_btn.pressed.disconnect(_on_refresh_pressed)


func _on_refresh_pressed():
	_search_id += 1
	var search_id := _search_id
	for row in lobby_list.get_children():
		row.queue_free()
	refresh_btn.disabled = true
	status_label.text = tr("SERVER_BROWSER_SEARCHING")
	status_label.show()

	var lobbies := await steam_manager.find_lobbies()
	# Left the browser, or a newer search started, while Steam answered
	if search_id != _search_id:
		return

	refresh_btn.disabled = false
	status_label.text = tr("SERVER_BROWSER_EMPTY")
	status_label.visible = lobbies.is_empty()
	for lobby in lobbies:
		_add_row(lobby)
	if lobbies.is_empty():
		refresh_btn.grab_focus()
	else:
		(lobby_list.get_child(0) as Button).grab_focus()


func _add_row(lobby: Dictionary):
	var level := lobby["level"] as LevelManager.LevelName
	var where := (
		tr("SERVER_BROWSER_IN_LOBBY") if level == LevelManager.LevelName.LEVEL_SELECT_LABEL
		else tr(level_manager.level_name_map[level])
	)
	var row := Button.new()
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.text = tr("SERVER_BROWSER_ROW").format({
		"host": lobby["host_name"],
		"members": lobby["members"],
		"max_members": lobby["max_members"],
		"where": where,
	})
	row.pressed.connect(audio_manager.play_menu_click)
	row.pressed.connect(play_menu_state.join_game.bind(lobby["game_id"], self))
	lobby_list.add_child(row)


func _on_back_pressed():
	transitioned.emit(return_state, StateContext.NewWithReturn(self))


#override
func on_cancel_key_pressed():
	_on_back_pressed()


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if steam_manager == null:
		issues.append("steam_manager must not be empty")
	if level_manager == null:
		issues.append("level_manager must not be empty")
	if play_menu_state == null:
		issues.append("play_menu_state must not be empty")
	if audio_manager == null:
		issues.append("audio_manager must not be empty")

	return issues
