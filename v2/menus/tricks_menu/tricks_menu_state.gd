@tool
## Trick list built from TrickController.BINDINGS, so it always matches the live control scheme.
## From the main menu it opens over the TrickDemo level, demoing the row whose Show button is pressed
## on the active loadout; from pause it's the list alone.
class_name TricksMenuState extends MenuState

@export var menu_manager: MenuManager
@export var save_manager: SaveManager
@export var level_manager: LevelManager

const TRICK_ROW_SCENE := preload("res://menus/tricks_menu/components/trick_row.tscn")
const LIST_PADDING := 16
## Over the demo the list keeps a left column this share of a 16:9 screen wide; TrickDemo's camera
## frames the runs in the rest. TrickRow's column widths are sized to fit it.
const DEMO_LIST_WIDTH := 0.6

## Physics-driven tricks outside BINDINGS; each needs a TRICK_HOWTO_<NAME> localization key.
const HOWTO_TRICKS: Array[TrickController.Trick] = [
	TrickController.Trick.DRIFT,
	TrickController.Trick.BURNOUT,
	TrickController.Trick.BACKFLIP,
	TrickController.Trick.FRONTFLIP,
	TrickController.Trick.BUNNY_HOP,
]
## Physics-driven tricks listed under a state's tab instead of the how-to tab (same key rule). Listed
## before the stick tricks, so the base wheelie / stoppie lead their tabs.
const STATE_HOWTO_TRICKS: Dictionary = {
	TrickController.TrickState.WHEELIE:
	[TrickController.Trick.WHEELIE_SITTING, TrickController.Trick.DRIFT_WHEELIE],
	TrickController.TrickState.GROUND: [TrickController.Trick.STOPPIE],
}

@onready var state_tabs: TabContainer = %StateTabs
@onready var close_tricks_btn: Button = %CloseTricksBtn
@onready var clear_pin_btn: Button = %ClearPinBtn
@onready var bg_tint: ColorRect = %BGTint
@onready var content: AspectRatioContainer = %AspectRatioContainer
@onready var _full_ratio: float = content.ratio

var _rows: Array[TrickRow] = []
## One pressed Show button at a time, marking the trick on show.
var _show_group := ButtonGroup.new()
## Null from pause, where there's no demo level.
var _trick_demo: TrickDemo


## Built once here (BINDINGS is const) so the rows also preview in the editor. Before super so
## MenuState wires click sounds to the pin buttons.
func _ready():
	_build_tabs()
	super._ready()


func Enter(state_context: StateContext):
	return_ctx = state_context
	return_state = state_context.return_state

	if state_context is PauseStateContext:
		bg_tint.visible = state_context.show_bg_tint
	else:
		bg_tint.visible = false
		# Main menu's Enter swaps the menu level back in.
		level_manager.spawn_level(
			LevelManager.LevelName.TRICK_DEMO_LEVEL, InputStateManager.InputState.IN_MENU
		)
		_trick_demo = level_manager.current_level.get_node("%TrickDemo")
		_trick_demo.camera.make_current()
		var player_def := save_manager.get_player_definition()
		_trick_demo.show_rider(player_def.bike_skin, player_def.character_skin)
	for row in _rows:
		row.show_btn.visible = _trick_demo != null
		row.show_btn.set_pressed_no_signal(false)
	content.ratio = _full_ratio * (DEMO_LIST_WIDTH if _trick_demo else 1.0)
	content.alignment_horizontal = (
		AspectRatioContainer.ALIGNMENT_BEGIN if _trick_demo else AspectRatioContainer.ALIGNMENT_CENTER
	)

	_refresh_pins()
	ui.show()

	close_tricks_btn.pressed.connect(_on_close_tricks_pressed)
	clear_pin_btn.pressed.connect(_on_clear_pin_pressed)


func Exit(_state_context: StateContext):
	ui.hide()
	_trick_demo = null
	close_tricks_btn.pressed.disconnect(_on_close_tricks_pressed)
	clear_pin_btn.pressed.disconnect(_on_clear_pin_pressed)


## One tab per trick state, listing only the tricks bound there.
func _build_tabs():
	for state in TrickController.BINDINGS:
		var list := _add_tab(TrickController.TrickState.keys()[state].capitalize())
		for trick: TrickController.Trick in STATE_HOWTO_TRICKS.get(state, []):
			_add_row(list, state).populate_howto(trick)
		var bindings: Dictionary = TrickController.BINDINGS[state]
		for gesture in bindings:
			for dir in TrickController.Dir.values():
				var trick: TrickController.Trick = bindings[gesture][dir]
				if trick != TrickController.Trick.NONE:
					_add_row(list, state).populate_stick(state, trick, gesture, dir)

	var howto_list := _add_tab("TRICKS_HOWTO_TAB")
	for trick in HOWTO_TRICKS:
		_add_row(howto_list, TrickController.TrickState.NONE).populate_howto(trick)


## Adds a scrolling tab and returns its row list.
func _add_tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var padding := MarginContainer.new()
	padding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, LIST_PADDING)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	padding.add_child(list)
	scroll.add_child(padding)
	state_tabs.add_child(scroll)
	state_tabs.set_tab_title(state_tabs.get_tab_count() - 1, title)
	return list


## `state` picks the demo run (see TrickDemo).
func _add_row(list: VBoxContainer, state: TrickController.TrickState) -> TrickRow:
	var row: TrickRow = TRICK_ROW_SCENE.instantiate()
	row.pinnable = true
	list.add_child(row)
	row.pin_pressed.connect(_on_pin_pressed)
	row.show_btn.button_group = _show_group
	row.show_btn.pressed.connect(_show_trick.bind(row, state))
	_rows.append(row)
	return row


## Show is only visible over the demo, so _trick_demo is set.
func _show_trick(row: TrickRow, state: TrickController.TrickState):
	_trick_demo.play(row.trick_type, state)


## Toggles the row's pin.
func _on_pin_pressed(pin: String):
	var pins: Array = save_manager.current_save["pinned_tricks"].duplicate()
	if pin in pins:
		pins.erase(pin)
	else:
		pins.append(pin)
	save_manager.update_save("pinned_tricks", pins, true, true)
	_refresh_pins()


func _on_clear_pin_pressed():
	save_manager.update_save("pinned_tricks", [], true, true)
	_refresh_pins()


func _refresh_pins():
	var pins: Array = save_manager.current_save["pinned_tricks"]
	clear_pin_btn.disabled = pins.is_empty()
	for row in _rows:
		row.set_pinned(row.pin in pins)


func _on_close_tricks_pressed():
	transitioned.emit(return_state, StateContext.NewWithReturn(self))


#override
func on_cancel_key_pressed():
	_on_close_tricks_pressed()


#override
func on_tab_key_pressed(dir: int):
	state_tabs.current_tab = wrapi(state_tabs.current_tab + dir, 0, state_tabs.get_tab_count())
