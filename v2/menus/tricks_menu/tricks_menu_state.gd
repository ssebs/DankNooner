@tool
## Trick list built from TrickController.BINDINGS, so it always matches the live control scheme.
class_name TricksMenuState extends MenuState

@export var menu_manager: MenuManager
@export var save_manager: SaveManager

const TRICK_ROW_SCENE := preload("res://menus/tricks_menu/components/trick_row.tscn")
const LIST_PADDING := 16

## Physics-driven tricks outside BINDINGS; each needs a TRICK_HOWTO_<NAME> localization key.
const HOWTO_TRICKS: Array[TrickController.Trick] = [
	TrickController.Trick.DRIFT,
	TrickController.Trick.BURNOUT,
	TrickController.Trick.BACKFLIP,
	TrickController.Trick.FRONTFLIP,
]

@onready var state_tabs: TabContainer = %StateTabs
@onready var close_tricks_btn: Button = %CloseTricksBtn
@onready var clear_pin_btn: Button = %ClearPinBtn
@onready var bg_tint: ColorRect = %BGTint

var _rows: Array[TrickRow] = []


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

	_refresh_pins()
	ui.show()

	close_tricks_btn.pressed.connect(_on_close_tricks_pressed)
	clear_pin_btn.pressed.connect(_on_clear_pin_pressed)


func Exit(_state_context: StateContext):
	ui.hide()
	close_tricks_btn.pressed.disconnect(_on_close_tricks_pressed)
	clear_pin_btn.pressed.disconnect(_on_clear_pin_pressed)


## One tab per trick state, listing only the tricks bound there.
func _build_tabs():
	for state in TrickController.BINDINGS:
		var list := _add_tab(TrickController.TrickState.keys()[state].capitalize())
		var bindings: Dictionary = TrickController.BINDINGS[state]
		for gesture in bindings:
			for dir in TrickController.Dir.values():
				var trick: TrickController.Trick = bindings[gesture][dir]
				if trick != TrickController.Trick.NONE:
					_add_row(list).populate_stick(state, trick, gesture, dir)

	var howto_list := _add_tab("TRICKS_HOWTO_TAB")
	for trick in HOWTO_TRICKS:
		_add_row(howto_list).populate_howto(trick)


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


func _add_row(list: VBoxContainer) -> TrickRow:
	var row: TrickRow = TRICK_ROW_SCENE.instantiate()
	row.pinnable = true
	list.add_child(row)
	row.pin_pressed.connect(_on_pin_pressed)
	_rows.append(row)
	return row


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
