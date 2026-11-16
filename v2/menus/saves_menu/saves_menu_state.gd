@tool
## Profile: tabs on the left 3/4, the active save's ProfileCard and challenges on the right 1/4.
## Save Slots tab: the active save's username, then a card per save on disk (this build's only, see
## SaveManager.slot_path) and empty cards in the lowest free slots up to MIN_CARDS. From the pause
## menu (a PauseStateContext) it's rename-only: no empty cards, load or delete. Cards are rebuilt,
## previews included, on Enter; the Career table and challenge lists follow the active save.
class_name SavesMenuState extends MenuState

@export var save_manager: SaveManager
@export var input_state_manager: InputStateManager

const MIN_CARDS := 3
const SAVE_CARD_SCENE := preload("res://menus/saves_menu/components/save_card.tscn")
const THUMB_SCENE := preload("res://utils/components/thumbnail_3d.tscn")
const CARD_WIDTH := 220.0
const REWARD_THUMB_SIZE := Vector2(172, 112)
## A reward not yet earned, matching LoadoutBar's locked slots.
const REWARD_LOCKED_ALPHA := LoadoutBar.LOCKED_ALPHA
## Career column widths, so every grid lines up.
const CAREER_NAME_WIDTH := 200.0
const CAREER_VALUE_WIDTH := 96.0
## A bike type's cell for a stat it has no entry for.
const CAREER_NONE := "-"
const CAREER_SECTION_FONT_SIZE := 22
const CAREER_FONT_SIZE := 17
const CAREER_SMALL_FONT_SIZE := 14
## Text emphasis on white, Material style: secondary (headers, sub-labels, per-type values) and
## disabled (no entry).
const CAREER_SECONDARY := Color(1, 1, 1, 0.6)
const CAREER_DISABLED := Color(1, 1, 1, 0.3)
const CAREER_DIVIDER := Color(1, 1, 1, 0.08)

@onready var _bg_tint: ColorRect = %BGTint
@onready var _tabs: PromptTabContainer = %Tabs
@onready var _username_edit: LineEdit = %UsernameEdit
@onready var _profile_card: ProfileCard = %ProfileCard
@onready var _cards: HBoxContainer = %Cards
@onready var _career_list: VBoxContainer = %CareerList
@onready var _bike_list: VBoxContainer = %BikeList
@onready var _challenge_list: VBoxContainer = %ChallengeList
@onready var _close_btn: Button = %CloseBtn
@onready var _confirm_box: Control = %ConfirmBox
@onready var _confirm_label: Label = %ConfirmLabel
@onready var _confirm_yes_btn: Button = %ConfirmYesBtn
@onready var _confirm_no_btn: Button = %ConfirmNoBtn

## slot -> its SaveCard
var _card_by_slot: Dictionary = {}
## Runs on the confirm box's yes (load or delete).
var _on_confirm: Callable
## Opened mid-game: swapping saves under a live session isn't allowed.
var _in_session: bool = false


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if save_manager == null:
		warnings.append("save_manager is not set")
	if input_state_manager == null:
		warnings.append("input_state_manager is not set")
	return warnings


func Enter(state_context: StateContext):
	return_state = state_context.return_state
	_in_session = state_context is PauseStateContext
	_bg_tint.visible = _in_session and state_context.show_bg_tint
	ui.show()
	_confirm_box.hide()
	_show_active()
	_username_edit.text_submitted.connect(_on_username_submitted)
	_username_edit.focus_exited.connect(_on_username_focus_exited)
	_close_btn.pressed.connect(_on_close_pressed)
	_confirm_yes_btn.pressed.connect(_on_confirm_yes)
	_confirm_no_btn.pressed.connect(_confirm_box.hide)
	input_state_manager.device_changed.connect(_tabs.show_prompts)
	_tabs.show_prompts(input_state_manager.is_gamepad)
	_build_cards()


func Exit(_state_context: StateContext):
	ui.hide()
	_username_edit.text_submitted.disconnect(_on_username_submitted)
	_username_edit.focus_exited.disconnect(_on_username_focus_exited)
	_close_btn.pressed.disconnect(_on_close_pressed)
	_confirm_yes_btn.pressed.disconnect(_on_confirm_yes)
	_confirm_no_btn.pressed.disconnect(_confirm_box.hide)
	input_state_manager.device_changed.disconnect(_tabs.show_prompts)
	for list: Node in [_cards, _career_list, _bike_list, _challenge_list]:
		for child in list.get_children():
			child.queue_free()
	_card_by_slot.clear()


## progression.stats, a section per category: a line per stat, columns Total then each bike type.
## Only stats the save has show.
func _build_career():
	for child in _career_list.get_children():
		_career_list.remove_child(child)
		child.queue_free()
	var stats: Dictionary = save_manager.current_save["progression"].get("stats", {})
	var scopes: Array[Dictionary] = [stats.get("lifetime", {})]
	var columns: PackedStringArray = ["", "", tr("CAREER_TOTAL")]
	for bike_type in save_manager.bike_types:
		scopes.append(stats.get("by_type", {}).get(SaveManager.stat_type_key(bike_type), {}))
		columns.append(tr(bike_type.name_key))

	var riding := [
		[tr("CAREER_DISTANCE"), "", "distance", _format_distance],
		[tr("CAREER_TOP_SPEED"), "", "top_speed", _format_speed],
		[tr("CAREER_CRASHES"), "", "crashes", MoneyLabel.group_digits],
		[tr("CAREER_MONEY_EARNED"), "", "money_earned", MoneyLabel.format],
	]
	riding.append_array(_career_run_rows(tr("CAREER_AIRTIME"), "airtime"))
	var tricks := []
	for trick: String in TrickController.Trick.keys():
		tricks.append_array(_career_run_rows(tr("TRICK_NAME_" + trick), trick))
	var events := []
	for mode: String in GameModeType.Kind.keys():
		events.append([tr("EVENT_%s_NAME" % mode), tr("CAREER_PLAYED"), mode + "_played", MoneyLabel.group_digits])
		events.append(["", tr("CAREER_WINS"), mode + "_wins", MoneyLabel.group_digits])

	_add_career_section("CAREER_RIDING", riding, scopes, columns)
	_add_career_section("CAREER_TRICKS", tricks, scopes, columns)
	_add_career_section("CAREER_EVENTS", events, scopes, columns)
	if _career_list.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "CAREER_EMPTY"
		_career_list.add_child(empty)


## A run stat's lines (see StatsManager._add_runs): count, total time, best.
func _career_run_rows(title: String, key: String) -> Array:
	return [
		[title, tr("CAREER_COUNT"), key + "_count", MoneyLabel.group_digits],
		["", tr("CAREER_TIME"), key + "_secs", _format_secs],
		["", tr("CAREER_BEST"), key + "_best_secs", _format_secs],
	]


## rows: [title, sub-label, stat key, format(value) -> String]; a titled row starts a stat, its
## untitled rows follow. Lines missing from the lifetime scope (scopes[0]) are left out, and the
## section with them. Each stat is its own grid under a divider.
func _add_career_section(
	title_key: String, rows: Array, scopes: Array[Dictionary], columns: PackedStringArray
):
	var shown := rows.filter(func(row): return scopes[0].has(row[2]))
	if shown.is_empty():
		return
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)
	_career_list.add_child(section)
	var header := Label.new()
	header.theme_type_variation = &"TableHeaderLabel"
	header.add_theme_font_size_override("font_size", CAREER_SECTION_FONT_SIZE)
	header.text = title_key
	section.add_child(header)
	var grid := _add_career_grid(section, columns.size())
	for column in columns:
		_add_career_cell(grid, column, CAREER_SECONDARY, CAREER_SMALL_FONT_SIZE)
	for row: Array in shown:
		if row[0] != "":
			var divider := ColorRect.new()
			divider.color = CAREER_DIVIDER
			divider.custom_minimum_size.y = 1
			section.add_child(divider)
			grid = _add_career_grid(section, columns.size())
		_add_career_cell(grid, row[0], Color.WHITE, CAREER_FONT_SIZE)
		_add_career_cell(grid, row[1], CAREER_SECONDARY, CAREER_SMALL_FONT_SIZE)
		for i in scopes.size():
			if !scopes[i].has(row[2]):
				_add_career_cell(grid, CAREER_NONE, CAREER_DISABLED, CAREER_FONT_SIZE)
				continue
			# Total reads first; the per-type split is secondary.
			var color := Color.WHITE if i == 0 else CAREER_SECONDARY
			_add_career_cell(grid, row[3].call(scopes[i][row[2]]), color, CAREER_FONT_SIZE)


func _add_career_grid(section: VBoxContainer, columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("v_separation", 2)
	section.add_child(grid)
	return grid


## Name, sub-label, then values, right-aligned.
func _add_career_cell(grid: GridContainer, text: String, color: Color, font_size: int):
	var cell := Label.new()
	cell.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	cell.text = text
	cell.add_theme_color_override("font_color", color)
	cell.add_theme_font_size_override("font_size", font_size)
	cell.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var column := grid.get_child_count() % grid.columns
	cell.custom_minimum_size.x = CAREER_NAME_WIDTH if column == 0 else CAREER_VALUE_WIDTH
	if column >= 2:
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(cell)


## Saved distance is speed x seconds, and the HUD shows speed as mph.
func _format_distance(value: float) -> String:
	return "%.1f %s" % [value / 3600.0, tr("CAREER_DISTANCE_UNIT")]


func _format_speed(value: float) -> String:
	return "%d %s" % [int(value), tr("HUD_SPEED_UNIT")]


static func _format_secs(value: float) -> String:
	return "%.1fs" % value if value < 60.0 else RaceTask.format_time_ms(int(value * 1000.0))


## The active bike's challenges, and a mastery header (finished / listed) per bike type over its
## challenges. Rebuilt whenever the active save changes.
func _build_challenge_lists():
	for list: Node in [_bike_list, _challenge_list]:
		for child in list.get_children():
			list.remove_child(child)
			child.queue_free()
	var active_type := save_manager.get_player_definition().bike_skin.bike_type
	var progress := SaveManager.bike_challenge_progress(save_manager.current_save)
	ProfileCard.build_rows(_challenge_list, ProfileCard.challenge_rows(active_type.challenges, progress))
	for bike_type in save_manager.bike_types:
		var header := Label.new()
		header.theme_type_variation = &"Heading2Label"
		header.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var done := save_manager.mastery(bike_type)
		header.text = "%s  %d/%d" % [tr(bike_type.name_key), done, bike_type.challenges.size()]
		_bike_list.add_child(header)
		# Scrolls sideways so a long list doesn't widen the tab
		var scroll := ScrollContainer.new()
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_bike_list.add_child(scroll)
		var cards := HBoxContainer.new()
		cards.add_theme_constant_override("separation", 24)
		scroll.add_child(cards)
		var base := _base_skin(bike_type)
		var rewards := save_manager.mod_rewards().filter(func(r): return r["bike_type"] == bike_type)
		for i in bike_type.challenges.size():
			var challenge := bike_type.challenges[i]
			var one: Array[ChallengeDefinition] = [challenge]
			var row := ProfileCard.challenge_rows(one, progress)[0]
			# The last card shows the mod finishing the list earns, when its challenge has no own reward
			var is_mastery_card := i == bike_type.challenges.size() - 1 and challenge.reward_mod == null
			var source: Variant = null if is_mastery_card else challenge
			var reward: Array = rewards.filter(func(r): return r["challenge"] == source)
			_add_challenge_card(cards, base, row, reward[0] if !reward.is_empty() else {})


## A card: the reward's name, the reward (base bike wearing it, dimmed until earned), then the
## challenge's row. Cards in a row share its height (the HBox stretches them). reward: a
## SaveManager.mod_rewards entry, empty for none.
func _add_challenge_card(cards: Container, base: BikeSkinDefinition, row: Dictionary, reward: Dictionary):
	var card := PanelContainer.new()
	card.theme_type_variation = &"TrickRowPanel"
	card.custom_minimum_size.x = CARD_WIDTH
	cards.add_child(card)
	var body := VBoxContainer.new()
	card.add_child(body)
	if !reward.is_empty():
		var title := Label.new()
		title.add_theme_font_size_override("font_size", 20)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		title.text = GarageUI.skin_label(GarageUI.mod_file_name(reward["mod"]))
		body.add_child(title)
		var thumb: Thumbnail3D = THUMB_SCENE.instantiate()
		thumb.custom_minimum_size = REWARD_THUMB_SIZE
		thumb.modulate.a = 1.0 if reward["earned"] else REWARD_LOCKED_ALPHA
		body.add_child(thumb)
		var fitted: BikeSkinDefinition = base.duplicate()
		var mods: Array[BikeMod] = [reward["mod"]]
		fitted.mods = mods
		thumb.set_skin(Thumbnail3D.Type.BIKE, fitted)
	var typed: Array[Dictionary] = [row]
	ProfileCard.build_rows(body, typed)


## The type's base skin (the one no mastery gates), which its reward thumbnails wear.
func _base_skin(bike_type: BikeTypeDefinition) -> BikeSkinDefinition:
	var bases := SkinScanner.scan_skin_dir(GarageUI.BIKE_SKINS_DIR).values().map(load).filter(
		func(skin: BikeSkinDefinition): return skin.bike_type == bike_type and skin.unlock_mastery == 0
	)
	return bases[0]


func _build_cards():
	var saved := save_manager.saved_slots()
	var slots := saved.duplicate()
	var free_slot := 1
	while !_in_session and slots.size() < MIN_CARDS:
		if free_slot not in saved:
			slots.append(free_slot)
		free_slot += 1
	slots.sort()

	for slot in slots:
		var card: SaveCard = SAVE_CARD_SCENE.instantiate()
		_cards.add_child(card)
		_card_by_slot[slot] = card
		_wire_button_click_sounds(card)
		card.new_pressed.connect(_load_slot.bind(slot))
		card.load_pressed.connect(_on_load_pressed.bind(slot))
		card.delete_pressed.connect(_on_delete_pressed.bind(slot))
		card.name_submitted.connect(_on_slot_name_submitted.bind(slot))
		_show_card(slot)
	_mark_active()


## Redraws the card's preview, so only for a slot whose save changed.
func _show_card(slot: int):
	var save_dict := save_manager.read_slot(slot)
	_card_by_slot[slot].show_save(slot, save_dict, save_manager.is_current_version(save_dict))


func _mark_active():
	for slot in _card_by_slot:
		_card_by_slot[slot].set_active(slot == save_manager.save_slot, _in_session)


## Loading an empty slot starts a new save there.
func _load_slot(slot: int):
	var was_empty := save_manager.read_slot(slot).is_empty()
	save_manager.switch_slot(slot)
	if was_empty:
		_show_card(slot)
	_mark_active()
	_show_active()


## Deleting the active save may start a new one in its slot (SaveManager.delete_slot).
func _delete_slot(slot: int):
	save_manager.delete_slot(slot)
	_show_card(slot)
	_mark_active()
	_show_active()


## The username field and profile card follow the active save.
func _show_active():
	_username_edit.text = save_manager.get_player_definition().username
	_profile_card.show_save(
		save_manager.save_slot, save_manager.current_save, save_manager.get_player_definition()
	)
	_build_career()
	_build_challenge_lists()


func _on_slot_name_submitted(slot_name: String, slot: int):
	save_manager.rename_slot(slot, slot_name)
	if slot == save_manager.save_slot:
		_show_active()


func _on_load_pressed(slot: int):
	_confirm(tr("SAVE_LOAD_CONFIRM") % _slot_name(slot), "LOAD_LABEL", _load_slot.bind(slot))


func _on_delete_pressed(slot: int):
	_confirm(tr("GARAGE_DELETE_CONFIRM") % _slot_name(slot), "DELETE_LABEL", _delete_slot.bind(slot))


func _slot_name(slot: int) -> String:
	return SaveCard.display_name(slot, save_manager.read_slot(slot))


func _confirm(question: String, yes_label: String, on_yes: Callable):
	_confirm_label.text = question
	_confirm_yes_btn.text = yes_label
	_on_confirm = on_yes
	_confirm_box.show()


func _on_confirm_yes():
	_confirm_box.hide()
	_on_confirm.call()


func _on_username_submitted(username: String):
	var player_def := save_manager.get_player_definition()
	player_def.username = username
	save_manager.update_save("player_definition", player_def, true, true)


func _on_username_focus_exited():
	_on_username_submitted(_username_edit.text)


func _on_close_pressed():
	transitioned.emit(return_state, StateContext.NewWithReturn(self))


#override
func on_cancel_key_pressed():
	if _confirm_box.visible:
		_confirm_box.hide()
		return
	_on_close_pressed()


#override
func on_tab_key_pressed(dir: int):
	_tabs.current_tab = wrapi(_tabs.current_tab + dir, 0, _tabs.get_tab_count())
