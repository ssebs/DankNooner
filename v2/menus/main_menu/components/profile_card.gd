## The active save: the rider in a circle, level and money, then the save name small. Clicking it
## opens the Saves menu (main + pause menus). The caret drops a panel with three tabs: today's
## dailies, up to MAX_CHALLENGES bike ChallengeRows, and the live leaderboard (fed by
## RidingHUDState). Career stats live in the Saves menu. Open/closed and
## the tab are shared by every card for the run, so the pause menu's pick is what the HUD shows.
class_name ProfileCard extends VBoxContainer

signal pressed

## LEADERBOARD stays last (see _on_tab_key_input).
enum Tab { DAILY, CHALLENGES, LEADERBOARD }

## Off: no hover, hand cursor or pressed.
@export var clickable: bool = true
## Off: no caret and the tabs can't be clicked; the panel just mirrors the shared state (the
## riding HUD).
@export var expandable: bool = true
## Off: the pill alone, never the panel (the Saves menu, which lists them itself).
@export var show_drop: bool = true
## On: an event's board (see show_board) always shows, open on the leaderboard, whatever the
## shared state (the riding HUD; pause can still look at challenges).
@export var board_overrides: bool = false
## > 0: the first auto-open waits this long on a closed panel before sliding (the main menu).
@export var auto_open_delay_secs: float = 0.0

const HOVER_MODULATE := Color(1.25, 1.25, 1.25)
const MAX_CHALLENGES := 5
const CARET_PULSE_SCALE := 1.3
const CARET_PULSE_SECS := 0.5
const CARET_PULSE_GAP_SECS := 1.2
const OPEN_SECS := 0.4
const CARET_RING_GROW := 4.0
const CHALLENGE_ROW_SCENE := preload("res://menus/main_menu/components/challenge_row.tscn")
## How long a challenge's progress / completion holds the panel open on its tab.
const CHALLENGE_PEEK_SECS := 3.0
const CHALLENGE_DONE_PEEK_SECS := 6.0

## Until the caret is first pressed the panel opens itself for a leaderboard or a new daily,
## and the caret pulses.
static var _opened_once: bool = false
static var _expanded: bool = false
static var _tab: Tab = Tab.LEADERBOARD
## The last board pushed (see show_board); empty headers = no board up.
static var _board_headers: PackedStringArray = PackedStringArray()
static var _board_rows: Array = []
## The board is an event's, not free roam's.
static var _board_is_event: bool = false

## A MoneyLabel, so a host can flash / pop it (the garage's purchases).
@onready var money_label: MoneyLabel = %MoneyLabel
## The level, so the HUD can pop it on XP.
@onready var level_label: Label = %LevelLabel
@onready var _pill: PanelContainer = %Pill
@onready var _portrait: SavePreview = %Portrait
@onready var _name_label: Label = %NameLabel
@onready var _caret: TextureButton = %CaretBtn
## A plain Control, so the Row's re-sort can't reset the caret's rotation.
@onready var _caret_slot: Control = %CaretSlot
@onready var _drop: Control = %Drop
@onready var _daily_tab: Button = %DailyTab
@onready var _challenges_tab: Button = %ChallengesTab
@onready var _leaderboard_tab: Button = %LeaderboardTab
@onready var _daily_list: VBoxContainer = %DailyList
@onready var _challenge_list: VBoxContainer = %ChallengeList
## Replace their lists once every challenge in them is finished.
@onready var _dailies_done: Label = %DailiesDone
@onready var _challenges_done: Label = %ChallengesDone
@onready var _leaderboard: RaceLeaderboard = %Leaderboard
@onready var _prev_tab_prompt: InputPrompt = %PrevTabPrompt
@onready var _next_tab_prompt: InputPrompt = %NextTabPrompt

var _caret_tween: Tween
var _open_tween: Tween
## Where the drop is headed; it stays visible while sliding shut.
var _drop_open: bool = false
## The drop's unrolled fraction (its scale.y), kept here because the card's layout resets scale.
var _reveal: float = 1.0
## The delayed auto-open already ran on this card.
var _slid_open: bool = false
## Held open on top of the shared state (see set_peek).
var _peek: bool = false
## The tab on screen, which can differ from _tab (no board, or board_overrides).
var _shown_tab: Tab = Tab.CHALLENGES
var _input_state_manager: InputStateManager
## "tab:title" -> the progress last shown, to juice what went up (see show_challenges).
var _challenge_progress: Dictionary[String, float] = {}
## Ticks msec the challenge peek closes at; 0 when not peeking.
var _challenge_peek_until: int = 0
## Every one of today's dailies / the shown bike type's challenges is finished.
var _daily_done: bool = false
var _bike_done: bool = false


func _ready():
	_caret_slot.visible = expandable
	# Clickable while expandable or peeking (see _apply).
	_daily_tab.pressed.connect(_on_tab_pressed.bind(Tab.DAILY))
	_challenges_tab.pressed.connect(_on_tab_pressed.bind(Tab.CHALLENGES))
	_leaderboard_tab.pressed.connect(_on_tab_pressed.bind(Tab.LEADERBOARD))
	if expandable:
		_caret.focus_mode = FOCUS_ALL
		# A TextureButton draws no focus style, so ring it with the buttons' one, hollow.
		var ring: StyleBoxFlat = get_theme_stylebox("focus", "Button").duplicate()
		ring.draw_center = false
		_caret.draw.connect(func():
			if _caret.has_focus():
				_caret.draw_style_box(ring, Rect2(Vector2.ZERO, _caret.size).grow(CARET_RING_GROW))
		)
		_caret.focus_entered.connect(_caret.queue_redraw)
		_caret.focus_exited.connect(_caret.queue_redraw)
		_caret.pressed.connect(_on_caret_pressed)
		_caret.gui_input.connect(_on_tab_key_input.bind(_caret))
		_pill.gui_input.connect(_on_tab_key_input.bind(_pill))
		_input_state_manager = get_tree().get_first_node_in_group(
			UtilsConstants.GROUPS["InputStateManager"]
		)
		_input_state_manager.device_changed.connect(_show_tab_prompts.unbind(1))
		for focusable: Control in [_pill, _caret]:
			focusable.focus_entered.connect(_show_tab_prompts)
			focusable.focus_exited.connect(_show_tab_prompts)
	_apply(true)
	if !clickable:
		_pill.mouse_default_cursor_shape = CURSOR_ARROW
		return
	_pill.focus_mode = FOCUS_ALL
	# The caret sits inside the pill, so geometric focus search never picks it.
	if expandable:
		_pill.focus_neighbor_right = _pill.get_path_to(_caret)
		_caret.focus_neighbor_left = _caret.get_path_to(_pill)
	# Focus borrows the buttons' focus border color.
	var pill_style: StyleBoxFlat = _pill.get_theme_stylebox("panel")
	var focus_style: StyleBoxFlat = pill_style.duplicate()
	var button_focus: StyleBoxFlat = get_theme_stylebox("focus", "Button")
	focus_style.border_color = button_focus.border_color
	_pill.focus_entered.connect(func(): _pill.add_theme_stylebox_override("panel", focus_style))
	_pill.focus_exited.connect(func(): _pill.add_theme_stylebox_override("panel", pill_style))
	_pill.gui_input.connect(_on_pill_gui_input)
	_pill.mouse_entered.connect(func(): _pill.modulate = HOVER_MODULATE)
	_pill.mouse_exited.connect(func(): _pill.modulate = Color.WHITE)


## Picks up a change another card made while this one was hidden (the HUD behind pause).
func _notification(what: int):
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready() and is_visible_in_tree():
		_apply()
	# Runs after VBoxContainer's own sort, which put the drop back to scale 1.
	elif what == NOTIFICATION_SORT_CHILDREN and is_node_ready():
		_drop.scale.y = _reveal


## The portrait, text and their containers pass clicks up to the pill; the caret keeps its own.
func _on_pill_gui_input(event: InputEvent):
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and !event.pressed
	):
		pressed.emit()
	# A PanelContainer isn't a Button, so a focused pill takes ui_accept itself.
	elif event.is_action_pressed("ui_accept"):
		_pill.accept_event()
		pressed.emit()


## LB/RB on the focused card flips its tabs, ahead of the menu's own (InputStateManager's
## _unhandled_input).
func _on_tab_key_input(event: InputEvent, focused: Control):
	var dir := 0
	if event.is_action_pressed("ui_tab_prev"):
		dir = -1
	elif event.is_action_pressed("ui_tab_next"):
		dir = 1
	if dir == 0:
		return
	focused.accept_event()
	# Leaderboard is the last tab, so dropping it from the wrap skips it while it's hidden.
	var tab_count := Tab.size() if _leaderboard_tab.visible else Tab.LEADERBOARD
	_on_tab_pressed(wrapi(_shown_tab + dir, 0, tab_count) as Tab)


## The LB/RB prompts only while LB/RB work: a gamepad on the focused card.
func _show_tab_prompts():
	var on := _input_state_manager.is_gamepad and (_pill.has_focus() or _caret.has_focus())
	for prompt: InputPrompt in [_prev_tab_prompt, _next_tab_prompt]:
		# refresh() hides it when the action is unbound.
		prompt.refresh(true)
		prompt.visible = prompt.visible and on


func show_save(slot: int, save_dict: Dictionary, player_def: PlayerDefinition) -> void:
	show_stats(player_def)
	show_challenges(player_def.bike_skin.bike_type, save_dict, false)
	_name_label.text = SaveCard.display_name(slot, save_dict)
	_portrait.show_player(player_def)


## For a host's focus neighbors; only focusable when clickable.
func get_focus_target() -> Control:
	return _pill


## Level + money only; no portrait redraw, so it's cheap to call every frame.
func show_stats(player_def: PlayerDefinition) -> void:
	level_label.text = SaveCard.level_text(player_def)
	money_label.text = MoneyLabel.format(player_def.money)


## Today's dailies and the bike type's challenges, unfinished first. Rows are updated in place, so
## the riding HUD calls this every frame. juice: a row whose count went up pops (punches when it
## finishes) and the panel peeks open.
func show_challenges(bike_type: BikeTypeDefinition, save_dict: Dictionary, juice: bool) -> void:
	var shown := _challenge_progress
	_challenge_progress = {}
	var dailies := challenge_rows(
		SaveManager.daily_challenges(save_dict), SaveManager.daily_progress(save_dict)
	)
	var daily_done := _show_rows_or_done(
		Tab.DAILY, _daily_list, _dailies_done, dailies, _daily_done, shown, juice
	)
	# Named for the type, so it's clear which bike's list this is (main menu: the active loadout's).
	_challenges_tab.text = bike_type.name_key
	_challenges_done.text = tr("BIKE_CHALLENGES_DONE").format({"type": tr(bike_type.name_key)})
	var bike := challenge_rows(bike_type.challenges, SaveManager.bike_challenge_progress(save_dict))
	# Unfinished sort first, so the slice is all done only when the whole list is.
	var bike_done := _show_rows_or_done(
		Tab.CHALLENGES,
		_challenge_list,
		_challenges_done,
		bike.slice(0, MAX_CHALLENGES),
		_bike_done,
		shown,
		juice
	)
	if daily_done != _daily_done or bike_done != _bike_done:
		_daily_done = daily_done
		_bike_done = bike_done
		_apply()
	if _challenge_peek_until > 0 and Time.get_ticks_msec() >= _challenge_peek_until:
		_challenge_peek_until = 0
		_apply()


## See RaceLeaderboard.set_board. Kept for every card, so the pause menu shows the HUD's board.
func show_board(headers: PackedStringArray, rows: Array, is_event: bool) -> void:
	var changed := _board_headers.is_empty() or is_event != _board_is_event
	_board_headers = headers
	_board_rows = rows
	_board_is_event = is_event
	if changed:
		_apply()
	else:
		_leaderboard.set_board(headers, rows)


## Opens the panel while `on`, without touching the shared state (HUD: the loadouts hold).
func set_peek(on: bool) -> void:
	_peek = on
	_apply()


func clear_board() -> void:
	_board_headers = PackedStringArray()
	_board_rows = []
	_leaderboard.clear()
	_apply()


## Rows (see build_rows) for challenges, unfinished first. progress_by_path: resource path ->
## progress.
static func challenge_rows(
	challenges: Array[ChallengeDefinition], progress_by_path: Dictionary
) -> Array[Dictionary]:
	var todo: Array[Dictionary] = []
	var done: Array[Dictionary] = []
	for challenge in challenges:
		var progress: float = progress_by_path.get(challenge.resource_path, 0.0)
		var row := {
			"title": challenge.title(),
			"progress": progress,
			"target": challenge.target,
			"money": challenge.money,
			"xp": challenge.xp,
		}
		(done if progress >= challenge.target else todo).append(row)
	todo.append_array(done)
	return todo


## Also builds the Saves menu's lists.
static func build_rows(list: VBoxContainer, entries: Array[Dictionary]):
	for entry in entries:
		var row: ChallengeRow = CHALLENGE_ROW_SCENE.instantiate()
		list.add_child(row)
		row.show_challenge(
			entry["title"], entry["progress"], entry["target"], entry.get("money", 0), entry.get("xp", 0)
		)


## rows via _show_rows, or `done` in their place once every one is finished (punching it as the last
## one finishes, with juice). was_done: the last call's result. Returns whether all are finished.
func _show_rows_or_done(
	tab: Tab,
	list: VBoxContainer,
	done: Label,
	rows: Array,
	was_done: bool,
	shown: Dictionary,
	juice: bool
) -> bool:
	var all_done := !rows.is_empty() and rows.all(func(row): return row["progress"] >= row["target"])
	_show_rows(tab, list, [] if all_done else rows, shown, juice)
	if all_done and !was_done and juice:
		HUDFlash.punch(done)
		_peek_challenges(CHALLENGE_DONE_PEEK_SECS)
	return all_done


## shown: _challenge_progress as it was before this refresh.
func _show_rows(tab: Tab, list: VBoxContainer, rows: Array, shown: Dictionary, juice: bool):
	if rows.size() != list.get_child_count():
		for child in list.get_children():
			list.remove_child(child)
			child.queue_free()
		var typed: Array[Dictionary] = []
		typed.assign(rows)
		build_rows(list, typed)
	for i in rows.size():
		var entry: Dictionary = rows[i]
		var row: ChallengeRow = list.get_child(i)
		row.show_challenge(
			entry["title"], entry["progress"], entry["target"], entry.get("money", 0), entry.get("xp", 0)
		)
		var key := "%d:%s" % [tab, entry["title"]]
		_challenge_progress[key] = entry["progress"]
		if juice and int(entry["progress"]) > int(shown.get(key, entry["progress"])):
			var done: bool = entry["progress"] >= entry["target"]
			if done:
				HUDFlash.punch(row)
			else:
				HUDFlash.pop(row)
			_peek_challenges(CHALLENGE_DONE_PEEK_SECS if done else CHALLENGE_PEEK_SECS)


## Opens the panel on the rider's own tab; progress never switches it.
func _peek_challenges(secs: float):
	_challenge_peek_until = maxi(_challenge_peek_until, Time.get_ticks_msec() + int(secs * 1000.0))
	_apply()


## Unrolls the panel down from the pill, or rolls it back up, from wherever it is now.
func _slide(open: bool, delay: float = 0.0):
	_drop_open = open
	if _open_tween != null:
		_open_tween.kill()
	_drop.pivot_offset = Vector2.ZERO
	if open and !_drop.visible:
		_set_reveal(0.0)
	_open_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if delay > 0.0:
		_open_tween.tween_interval(delay)
	if open:
		_open_tween.tween_callback(_drop.show)
	_open_tween.tween_method(_set_reveal, _reveal, 1.0 if open else 0.0, OPEN_SECS)
	_open_tween.parallel().tween_property(_caret, "rotation", 0.0 if open else PI, OPEN_SECS)
	if !open:
		_open_tween.tween_callback(_drop.hide)


func _set_reveal(reveal: float):
	_reveal = reveal
	_drop.scale.y = reveal


func _on_caret_pressed():
	# Mid-slide (or still waiting to auto-open) flips from what's on screen.
	if _open_tween != null:
		_open_tween.kill()
		_drop_open = _drop.visible
	_expanded = !_drop.visible
	_opened_once = true
	_apply()


func _on_tab_pressed(tab: Tab):
	_tab = tab
	_apply()


## Shows the shared open/closed state and tab; the leaderboard tab is hidden while no board is
## up (always on the main menu). `snap`: no slide (first draw).
func _apply(snap: bool = false):
	var has_board := !_board_headers.is_empty()
	var expanded := _expanded
	if !_opened_once:
		# TODO: also open for an unseen daily (Progression.md#dailies).
		expanded = has_board
	var tab := Tab.CHALLENGES if _tab == Tab.LEADERBOARD and !has_board else _tab
	if _challenge_peek_until > 0:
		expanded = true
	if board_overrides and has_board and _board_is_event:
		expanded = true
		tab = Tab.LEADERBOARD
	expanded = (expanded or _peek) and show_drop
	_shown_tab = tab

	# Display-only (the riding HUD) shows just the active tab, except while peeking (loadouts held,
	# cursor out), when they're all clickable.
	var all_tabs := expandable or _peek
	_daily_tab.visible = all_tabs or tab == Tab.DAILY
	_challenges_tab.visible = all_tabs or tab == Tab.CHALLENGES
	_leaderboard_tab.visible = has_board and (all_tabs or tab == Tab.LEADERBOARD)
	for tab_btn: Button in [_daily_tab, _challenges_tab, _leaderboard_tab]:
		tab_btn.mouse_filter = MOUSE_FILTER_STOP if all_tabs else MOUSE_FILTER_IGNORE
	_daily_tab.set_pressed_no_signal(tab == Tab.DAILY)
	_challenges_tab.set_pressed_no_signal(tab == Tab.CHALLENGES)
	_leaderboard_tab.set_pressed_no_signal(tab == Tab.LEADERBOARD)
	_daily_list.visible = tab == Tab.DAILY and !_daily_done
	_dailies_done.visible = tab == Tab.DAILY and _daily_done
	_challenge_list.visible = tab == Tab.CHALLENGES and !_bike_done
	_challenges_done.visible = tab == Tab.CHALLENGES and _bike_done
	_leaderboard.visible = tab == Tab.LEADERBOARD
	if has_board:
		_leaderboard.set_board(_board_headers, _board_rows)

	var delayed := expanded and !_opened_once and auto_open_delay_secs > 0.0 and !_slid_open
	if snap:
		_drop_open = expanded and !delayed
		_drop.visible = _drop_open
		_set_reveal(1.0)
		_caret.rotation = 0.0 if _drop_open else PI
	if delayed:
		_slid_open = true
		_slide(true, auto_open_delay_secs)
	elif expanded != _drop_open:
		_slide(expanded)
	if _caret_tween != null:
		_caret_tween.kill()
		_caret.scale = Vector2.ONE
	if !expandable or expanded or _opened_once:
		return
	_caret_tween = create_tween().set_loops()
	_caret_tween.tween_property(_caret, "scale", Vector2.ONE * CARET_PULSE_SCALE, CARET_PULSE_SECS)
	_caret_tween.tween_property(_caret, "scale", Vector2.ONE, CARET_PULSE_SECS)
	_caret_tween.tween_interval(CARET_PULSE_GAP_SECS)
