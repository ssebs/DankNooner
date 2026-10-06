## GTA-style garage list: a Profile tab, a tab per loadout and a `+` tab, each with a page stack.
## Focusing (or hovering) a row previews it; accepting applies or buys it. Edits and purchases
## mutate the in-memory PlayerDefinition and commit() saves them in one push. Hosts
## (CustomizeMenuState, GarageHUDState) wire preview_changed and pose_requested to a GarageSet and
## route back/tab input to go_back()/cycle_tab().
class_name GarageUI extends Control

## is_character: a character page, so the rider previews off the bike.
signal preview_changed(bike_def: BikeSkinDefinition, char_def: CharacterSkinDefinition, is_character: bool)
signal pose_requested
## Back was pressed on a tab's root page.
signal exit_requested

enum Page { ROOT, BIKE, BIKE_COLORS, CHARACTER, CHARACTER_COLORS }

const GARAGE_ROW := preload("res://menus/customize_menu/components/garage_row.tscn")
const BIKE_SKINS_DIR := "res://resources/bikes/skins/"
const CHARACTER_SKINS_DIR := PlayerDefinition.CHARACTER_SKINS_DIR
## Smaller than the shared theme's default, so the list stays out of the way of the preview.
const FONT_SIZE: int = 18
## The list scrolls past this, otherwise the panel fits its rows.
const MAX_LIST_HEIGHT: float = 480
## Longer loadout names ellipsize; the tab strip scrolls.
const TAB_MAX_WIDTH: float = 200

@onready var _tab_scroll: ScrollContainer = %TabScroll
@onready var _tabs: HBoxContainer = %Tabs
@onready var _money: Label = %Money
@onready var _title: Label = %Title
@onready var _count: Label = %Count
@onready var _back_btn: Button = %BackBtn
@onready var _set_active_btn: Button = %SetActiveBtn
@onready var _delete_btn: Button = %DeleteBtn
@onready var _leave_btn: Button = %LeaveBtn
@onready var _pose_btn: Button = %PoseBtn
@onready var _scroll: ScrollContainer = %Scroll
@onready var _rows: VBoxContainer = %Rows
@onready var _color_panel: Control = %ColorPanel
@onready var _picker: ColorPicker = %Picker
@onready var _color_done_btn: Button = %ColorDoneBtn
@onready var _confirm_box: Control = %ConfirmBox
@onready var _confirm_label: Label = %ConfirmLabel
@onready var _confirm_yes_btn: Button = %ConfirmYesBtn
@onready var _confirm_no_btn: Button = %ConfirmNoBtn

var _save_manager: SaveManager
var _player_def: PlayerDefinition
## skin_name -> res path
var _bikes: Dictionary = {}
var _characters: Dictionary = {}
## 0 = Profile, n = loadouts[n - 1].
var _tab: int = 0
var _pages: Array[Page] = []
## The unique-slot colors a *_COLORS page edits; _color_slot is the one in the picker.
var _colors: Array[Color] = []
var _color_slot: int = -1
## The bike or character def the open picker writes to.
var _color_target: Resource
## Runs on the confirm box's Yes.
var _on_confirm: Callable
## Row focused when the confirm box opened.
var _confirm_return_index: int = -1


func _ready():
	theme = theme.duplicate()
	theme.default_font_size = FONT_SIZE
	_back_btn.pressed.connect(go_back)
	_set_active_btn.pressed.connect(_set_active)
	_delete_btn.pressed.connect(_delete_loadout)
	_leave_btn.pressed.connect(_on_leave_pressed)
	_pose_btn.pressed.connect(pose_requested.emit)
	for color in UtilsConstants.SKIN_COLOR_PRESETS:
		if color not in _picker.get_presets():
			_picker.add_preset(color)
	_picker.color_changed.connect(_on_picker_color_changed)
	_color_done_btn.pressed.connect(_close_color_panel)
	_confirm_yes_btn.pressed.connect(_on_confirm_yes)
	_confirm_no_btn.pressed.connect(_close_confirm)


## Start on the active loadout's tab.
func open(save_manager: SaveManager):
	_save_manager = save_manager
	_player_def = save_manager.get_player_definition()
	_bikes = SkinScanner.scan_skin_dir(BIKE_SKINS_DIR)
	_characters = SkinScanner.scan_skin_dir(CHARACTER_SKINS_DIR)
	_fill_saved_colors()
	_color_panel.hide()
	_confirm_box.hide()
	_switch_tab(_player_def.active_loadout_index + 1)


## One save: one lobby push, one skin sync.
func commit():
	_save_manager.update_save("player_definition", _player_def, true, true)


## Closes the topmost thing: confirm box, color panel, page, then the garage.
func go_back():
	if _confirm_box.visible:
		_close_confirm()
	elif _color_panel.visible:
		_close_color_panel()
	elif _pages.size() > 1:
		_pages.pop_back()
		_rebuild()
	else:
		exit_requested.emit()


func _on_leave_pressed():
	if _color_panel.visible:
		_apply_picked_colors()
	exit_requested.emit()


## Skips the `+` tab, so cycling never creates a loadout.
func cycle_tab(dir: int):
	if _confirm_box.visible or _color_panel.visible:
		return
	_switch_tab(wrapi(_tab + dir, 0, _player_def.loadouts.size() + 1))


#region tabs
func _switch_tab(tab: int):
	# A mouse click can switch tabs under an open overlay.
	if _color_panel.visible:
		_apply_picked_colors()
	_confirm_box.hide()
	_tab = tab
	_pages = [Page.ROOT]
	_rebuild()


func _rebuild_tabs():
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	_add_tab(tr("GARAGE_PROFILE_TAB"), 0)
	for i in _player_def.loadouts.size():
		var loadout := _player_def.loadouts[i]
		_add_tab(loadout.name if loadout.name != "" else str(i + 1), i + 1)
	if _player_def.loadouts.size() < PlayerDefinition.MAX_LOADOUTS:
		var add_btn := Button.new()
		add_btn.text = "+"
		add_btn.focus_mode = Control.FOCUS_NONE
		add_btn.pressed.connect(_add_loadout)
		_tabs.add_child(add_btn)


func _add_tab(label: String, tab: int):
	var btn := Button.new()
	btn.text = label
	btn.toggle_mode = true
	btn.button_pressed = tab == _tab
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_switch_tab.bind(tab))
	_tabs.add_child(btn)
	btn.custom_minimum_size.x = minf(btn.get_minimum_size().x, TAB_MAX_WIDTH)
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if tab == _tab:
		# Deferred so the strip has laid out the new tabs.
		_tab_scroll.ensure_control_visible.call_deferred(btn)


## Copy of the active loadout.
func _add_loadout():
	var loadout := Loadout.new()
	loadout.from_dict(_player_def.loadouts[_player_def.active_loadout_index].to_dict())
	loadout.name = str(_player_def.loadouts.size() + 1)
	_player_def.loadouts.append(loadout)
	_switch_tab(_player_def.loadouts.size())


#endregion


#region pages
func _push(page: Page):
	_pages.append(page)
	_rebuild()


## Rebuild the current page's rows, focusing `focus_index` (-1 = the first button row).
func _rebuild(focus_index: int = -1):
	_money.text = _money_text(_player_def.money)
	_back_btn.visible = _pages.size() > 1
	var is_loadout_root := _tab != 0 and _pages.size() == 1
	_set_active_btn.visible = is_loadout_root
	_delete_btn.visible = is_loadout_root
	_rebuild_tabs()
	for child in _rows.get_children():
		# Not free(): this can run inside a row's own pressed signal.
		_rows.remove_child(child)
		child.queue_free()
	match _pages.back():
		Page.ROOT:
			if _tab == 0:
				_build_profile_root()
			else:
				_build_loadout_root()
		Page.BIKE:
			_build_bike_page()
		Page.BIKE_COLORS:
			_build_colors_page(tr("GARAGE_BIKE_COLORS"), _loadout().bike.mesh_res, _loadout().bike.colors)
		Page.CHARACTER:
			_build_character_page()
		Page.CHARACTER_COLORS:
			var character := _edited_character()
			_build_colors_page(tr("GARAGE_CHARACTER_COLORS"), character.mesh_res, character.colors)
	_scroll.custom_minimum_size.y = minf(_rows.get_combined_minimum_size().y, MAX_LIST_HEIGHT)
	# Before focusing, so the focused row's own preview wins.
	_preview_current()
	_focus_row(focus_index)


func _focus_row(index: int):
	if index < 0:
		for child in _rows.get_children():
			if child is GarageRow:
				child.grab_focus()
				return
	var row := _rows.get_child(mini(index, _rows.get_child_count() - 1))
	# A text row is a Label + LineEdit box.
	(row if row is GarageRow else row.get_child(1)).grab_focus()


func _build_profile_root():
	_title.text = tr("GARAGE_PROFILE_TAB")
	_add_text_row(tr("USERNAME_LABEL"), _player_def.username, func(t: String): _player_def.username = t)
	_add_row(
		tr("GARAGE_CHARACTER"),
		_skin_label(_player_def.default_character.skin_name) + " >",
		_push.bind(Page.CHARACTER)
	)
	_add_row(tr("GARAGE_CHARACTER_COLORS"), ">", _push.bind(Page.CHARACTER_COLORS))


func _build_loadout_root():
	var loadout := _loadout()
	_title.text = loadout.name
	_add_text_row(tr("NAME_LABEL"), loadout.name, _on_loadout_name_changed)
	_add_row(
		tr("GARAGE_BIKE"),
		_skin_label(_bikes.find_key(loadout.bike.base_res_path)) + " >",
		_push.bind(Page.BIKE)
	)
	_add_row(tr("GARAGE_BIKE_COLORS"), ">", _push.bind(Page.BIKE_COLORS))
	var character_label := tr("GARAGE_PROFILE_DEFAULT")
	if loadout.character != null:
		character_label = _skin_label(loadout.character.skin_name)
	_add_row(tr("GARAGE_CHARACTER"), character_label + " >", _push.bind(Page.CHARACTER))
	if loadout.character != null:
		_add_row(tr("GARAGE_CHARACTER_COLORS"), ">", _push.bind(Page.CHARACTER_COLORS))
	var is_active := _tab - 1 == _player_def.active_loadout_index
	_set_active_btn.text = tr("GARAGE_ACTIVE") if is_active else tr("SET_ACTIVE_LABEL")
	_set_active_btn.disabled = is_active
	_delete_btn.disabled = _player_def.loadouts.size() <= 1


func _build_bike_page():
	_title.text = tr("GARAGE_BIKE")
	var loadout := _loadout()
	for skin_name in _bikes:
		var path: String = _bikes[skin_name]
		var def := load(path) as BikeSkinDefinition
		_add_skin_row(
			skin_name,
			path,
			def.price,
			loadout.bike.base_res_path == path,
			_preview.bind(def, _shown_character()),
			_apply_bike.bind(path)
		)


func _build_character_page():
	_title.text = tr("GARAGE_CHARACTER")
	var current_name := ""
	if _tab == 0:
		current_name = _player_def.default_character.skin_name
	else:
		var loadout := _loadout()
		current_name = loadout.character.skin_name if loadout.character != null else ""
		_add_row(
			tr("GARAGE_PROFILE_DEFAULT"),
			_skin_label(_player_def.default_character.skin_name),
			_apply_character.bind(""),
			_preview.bind(loadout.bike, _player_def.default_character),
			loadout.character == null
		)
	for skin_name in _characters:
		var path: String = _characters[skin_name]
		var def := load(path) as CharacterSkinDefinition
		_add_skin_row(
			skin_name,
			path,
			def.price,
			skin_name == current_name,
			_preview.bind(_loadout().bike, def),
			_apply_character.bind(path)
		)


## One row per unique slot of `mesh_res`; pressing one opens the picker on it.
func _build_colors_page(title: String, mesh_res: PackedScene, colors: Array[Color]):
	_title.text = title
	_colors = SkinColor.get_unique_slot_colors(mesh_res, colors)
	for i in _colors.size():
		var row := _add_row(tr("GARAGE_COLOR_SLOT") % (i + 1), "", _open_color_panel.bind(i))
		row.set_swatch(_colors[i])


#endregion


#region rows
func _add_row(
	label: String, right: String, on_press: Callable, preview := Callable(), is_current := false
) -> GarageRow:
	var row: GarageRow = GARAGE_ROW.instantiate()
	_rows.add_child(row)
	row.setup(label, right, is_current)
	row.pressed.connect(on_press)
	_wire_focus(row, preview)
	return row


func _add_text_row(label: String, text: String, on_changed: Callable):
	var box := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = label
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Line up with GarageRow's label, which sits inside the button's content margin.
	var indent := StyleBoxEmpty.new()
	indent.content_margin_left = get_theme_stylebox("normal", "Button").content_margin_left
	name_label.add_theme_stylebox_override("normal", indent)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var entry := LineEdit.new()
	entry.text = text
	entry.max_length = 32
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.text_changed.connect(on_changed)
	box.add_child(name_label)
	box.add_child(entry)
	_rows.add_child(box)
	_wire_focus(entry, Callable())


## Hover focuses, so mouse and gamepad share one preview path.
func _wire_focus(control: Control, preview: Callable):
	control.mouse_entered.connect(control.grab_focus)
	control.focus_entered.connect(_on_row_focused.bind(control, preview))


func _add_skin_row(
	skin_name: String,
	path: String,
	price: int,
	is_current: bool,
	preview: Callable,
	apply: Callable
):
	var owned := _save_manager.is_owned(path)
	# Re-picking the current one would reset its colors.
	var on_press := (func(): pass) if is_current else _on_skin_pressed.bind(skin_name, path, price, apply)
	var row := _add_row(
		_skin_label(skin_name),
		tr("GARAGE_OWNED") if owned else _money_text(price),
		on_press,
		preview,
		is_current
	)
	if owned:
		row.set_right_color(GarageRow.OWNED_COLOR)
	elif _player_def.money < price:
		row.set_right_color(GarageRow.UNAFFORDABLE_COLOR)


## Rows are direct children of _rows, except a text row's LineEdit.
func _on_row_focused(control: Control, preview: Callable):
	var row: Node = control if control.get_parent() == _rows else control.get_parent()
	_count.text = "%d / %d" % [row.get_index() + 1, _rows.get_child_count()]
	if preview.is_valid():
		preview.call()
	else:
		_preview_current()


func _on_skin_pressed(skin_name: String, path: String, price: int, apply: Callable):
	if _save_manager.is_owned(path):
		apply.call()
		_rebuild(_focused_index())
		return
	if _player_def.money < price:
		return
	_open_confirm(
		tr("GARAGE_BUY_CONFIRM") % [_skin_label(skin_name), _money_text(price)],
		func():
			_save_manager.purchase(path, price)
			apply.call()
	)


#endregion


#region edits
func _on_loadout_name_changed(text: String):
	_loadout().name = text
	_title.text = text
	_rebuild_tabs()


func _apply_bike(path: String):
	# Via the base's own dict, so its ColorMod folds into colors like the hover preview shows.
	var bike := BikeSkinDefinition.new()
	bike.from_dict(load(path).to_dict())
	_loadout().bike = bike


## "" = back to the profile default (loadout tabs only).
func _apply_character(path: String):
	var character: CharacterSkinDefinition = null
	if path != "":
		# A copy, so color edits never touch the shared res:// def.
		character = CharacterSkinDefinition.new()
		character.from_dict(load(path).to_dict())
	if _tab == 0:
		_player_def.default_character = character
	else:
		_loadout().character = character


func _set_active():
	_player_def.active_loadout_index = _tab - 1
	_rebuild()


func _delete_loadout():
	var index := _tab - 1
	_player_def.loadouts.remove_at(index)
	if _player_def.active_loadout_index >= index:
		_player_def.active_loadout_index = maxi(_player_def.active_loadout_index - 1, 0)
	_switch_tab(mini(_tab, _player_def.loadouts.size()))


#endregion


#region color panel
func _open_color_panel(slot: int):
	_color_target = _loadout().bike if _pages.back() == Page.BIKE_COLORS else _edited_character()
	_color_slot = slot
	_picker.color = _colors[slot]
	_color_panel.show()
	_color_done_btn.grab_focus()


func _on_picker_color_changed(color: Color):
	_colors[_color_slot] = color
	var painted := _color_target.duplicate()
	painted.colors = _colors.duplicate()
	if painted is BikeSkinDefinition:
		_preview(painted, _shown_character())
	else:
		_preview(_loadout().bike, painted)


## Closing applies the picked color.
func _close_color_panel():
	_apply_picked_colors()
	_rebuild(_color_slot)


func _apply_picked_colors():
	_color_panel.hide()
	_color_target.colors = _colors.duplicate()


#endregion


#region confirm box
func _open_confirm(text: String, on_confirm: Callable):
	_on_confirm = on_confirm
	_confirm_return_index = _focused_index()
	_confirm_label.text = text
	_confirm_box.show()
	_confirm_no_btn.grab_focus()


func _on_confirm_yes():
	_on_confirm.call()
	_close_confirm()


func _close_confirm():
	_confirm_box.hide()
	_rebuild(_confirm_return_index)


#endregion


#region preview
## The real selection for the current tab.
func _preview_current():
	_preview(_loadout().bike, _shown_character())


func _preview(bike: BikeSkinDefinition, character: CharacterSkinDefinition):
	preview_changed.emit(bike, character, _pages.back() in [Page.CHARACTER, Page.CHARACTER_COLORS])


## Saved colors can be partial (a migrated variant). Full ones let GarageSet repaint instead of
## rebuilding, and a 1-color array would broadcast to every slot there.
func _fill_saved_colors():
	var defs: Array[Resource] = [_player_def.default_character]
	for loadout in _player_def.loadouts:
		defs.append(loadout.bike)
		if loadout.character != null:
			defs.append(loadout.character)
	for def in defs:
		if !def.colors.is_empty():
			def.colors = SkinColor.get_unique_slot_colors(def.mesh_res, def.colors)


#endregion


## Profile tab shows the active loadout.
func _loadout() -> Loadout:
	return _player_def.loadouts[_player_def.active_loadout_index if _tab == 0 else _tab - 1]


## Profile tab shows the profile default.
func _shown_character() -> CharacterSkinDefinition:
	var character := _loadout().character
	if _tab == 0 or character == null:
		return _player_def.default_character
	return character


## The character a CHARACTER_COLORS page edits.
func _edited_character() -> CharacterSkinDefinition:
	return _player_def.default_character if _tab == 0 else _loadout().character


func _focused_index() -> int:
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or !_rows.is_ancestor_of(focused):
		return 0
	return (focused if focused.get_parent() == _rows else focused.get_parent()).get_index()


## "naked_default" -> "Naked"
static func _skin_label(skin_name: String) -> String:
	return skin_name.trim_suffix("_default").capitalize()


## 15000 -> "$15,000"
static func _money_text(amount: float) -> String:
	var digits := str(int(amount))
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(-3)
	return "$" + digits + grouped
