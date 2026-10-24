@tool
## Settings tab for remapping controls. Edits a copy of settings "controls" (see ControlBindings);
## SettingsMenuState saves it.
class_name ControlsTab extends VBoxContainer

## Hold Esc this long while listening to clear the slot; a shorter tap cancels.
const CLEAR_HOLD_MSEC: int = 1000
## Stick/trigger travel needed to bind an axis, so resting drift doesn't.
const AXIS_BIND_THRESHOLD: float = 0.5
const CELL_WIDTH: float = 220.0

@onready var controls_grid: GridContainer = %ControlsGrid
@onready var hint_label: Label = %HintLabel
@onready var duplicate_label: Label = %DuplicateLabel

var _pending: Dictionary = {}
var _dirty := false
## action → slot → cell Button
var _cells: Dictionary = {}
## Cell waiting for an input; empty when not listening.
var _listen_action := ""
var _listen_slot := ""
var _esc_down_msec := -1


func _ready():
	if Engine.is_editor_hint():
		return
	duplicate_label.add_theme_color_override("font_color", SemanticColors.COLOR_VALUES[SemanticColors.Value.ERR])
	_build_grid()


## Esc is held to clear, so it's timed here rather than on release.
func _process(_delta: float):
	if _esc_down_msec != -1 and Time.get_ticks_msec() - _esc_down_msec >= CLEAR_HOLD_MSEC:
		_set_pending(_listen_action, _listen_slot, null)


## While listening, every input goes to the cell instead of the menu or game.
func _input(event: InputEvent):
	if _listen_action == "" or event is InputEventMouseMotion:
		return
	get_viewport().set_input_as_handled()

	if event is InputEventKey and event.physical_keycode == KEY_ESCAPE:
		if event.pressed and not event.echo:
			_esc_down_msec = Time.get_ticks_msec()
		elif not event.pressed and _esc_down_msec != -1:
			stop_listening()
	elif _is_bindable_press(event) and ControlBindings.accepts(_listen_slot, event):
		_set_pending(_listen_action, _listen_slot, ControlBindings.to_dict(event))


## Start from the saved overrides, dropping unsaved edits.
func load_controls(saved: Dictionary):
	_pending = saved.duplicate(true)
	_dirty = false
	stop_listening()


## Back to the Input Map defaults. Still needs Save.
func reset():
	_pending = {}
	_dirty = true
	_refresh()


func is_dirty() -> bool:
	return _dirty


func get_pending() -> Dictionary:
	return _pending.duplicate(true)


func stop_listening():
	_listen_action = ""
	_listen_slot = ""
	_esc_down_msec = -1
	_refresh()


## A header row, then per category a title row and a row per action.
func _build_grid():
	for header in ["CONTROLS_COL_ACTION", "KBM_LABEL", "GAMEPAD_LABEL", "CONTROLS_COL_ADDL"]:
		_add_grid_label(header).theme_type_variation = &"TableHeaderLabel"
	for category in UtilsConstants.CONTROL_CATEGORIES:
		_add_grid_label(category).add_theme_font_size_override("font_size", 32)
		for _i in ControlBindings.SLOTS.size():
			controls_grid.add_child(Control.new())

		for action in UtilsConstants.CONTROL_CATEGORIES[category]:
			_add_grid_label("ACTION_" + action.to_upper())
			_cells[action] = {}
			for slot in ControlBindings.SLOTS:
				# Buttons so keyboard/gamepad focus can reach them
				var cell := Button.new()
				cell.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
				cell.custom_minimum_size.x = CELL_WIDTH
				cell.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
				cell.add_theme_constant_override("icon_max_width", 40)
				cell.gui_input.connect(_on_cell_gui_input.bind(action, slot))
				controls_grid.add_child(cell)
				_cells[action][slot] = cell


func _add_grid_label(loc_key: String) -> Label:
	var label := Label.new()
	label.text = loc_key
	controls_grid.add_child(label)
	return label


## Redraw every cell from _pending and flag duplicates within each category.
func _refresh():
	var has_duplicates := false
	for category in UtilsConstants.CONTROL_CATEGORIES:
		var cells_by_binding := {}
		for action in UtilsConstants.CONTROL_CATEGORIES[category]:
			var slots := ControlBindings.resolve_slots(action, _pending)
			for slot in ControlBindings.SLOTS:
				var cell: Button = _cells[action][slot]
				_draw_cell(cell, slots[slot])
				if action == _listen_action and slot == _listen_slot:
					cell.text = "..."
					cell.icon = null
				if slots[slot] != null:
					cells_by_binding.get_or_add(str(ControlBindings.to_dict(slots[slot])), []).append(cell)

		for cells in cells_by_binding.values():
			if cells.size() > 1:
				has_duplicates = true
				for cell in cells:
					cell.modulate = SemanticColors.COLOR_VALUES[SemanticColors.Value.ERR]

	duplicate_label.visible = has_duplicates
	hint_label.text = "CONTROLS_LISTENING_LABEL" if _listen_action != "" else "CONTROLS_HINT_LABEL"


func _draw_cell(cell: Button, event: InputEvent):
	cell.modulate = Color.WHITE
	# Cells don't auto-translate, so the mouse button loc key needs tr() here.
	cell.text = tr(ControlBindings.event_text(event))
	cell.icon = ControlBindings.event_icon(event)


func _is_bindable_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventMouseButton:
		return event.pressed and ControlBindings.MOUSE_BUTTON_LABELS.has(event.button_index)
	if event is InputEventJoypadButton:
		return event.pressed and ControlBindings.JOY_BUTTON_ICONS.has(event.button_index)
	if event is InputEventJoypadMotion:
		return (
			absf(event.axis_value) >= AXIS_BIND_THRESHOLD
			and ControlBindings.JOY_AXIS_ICONS.has(ControlBindings.axis_key(event))
		)
	return false


## binding is a ControlBindings.to_dict() dict, or null to clear the slot.
func _set_pending(action: String, slot: String, binding: Variant):
	_pending.get_or_add(action, {})[slot] = binding
	_dirty = true
	stop_listening()


func _on_cell_gui_input(event: InputEvent, action: String, slot: String):
	var is_double_click: bool = event is InputEventMouseButton and event.pressed and event.double_click
	if is_double_click or event.is_action_pressed("ui_accept"):
		_cells[action][slot].accept_event()
		_listen_action = action
		_listen_slot = slot
		_esc_down_msec = -1
		_refresh()
