@tool
## Trick list built from TrickController.BINDINGS, so it always matches the live control scheme.
class_name TricksMenuState extends MenuState

@export var menu_manager: MenuManager

const HEADER_ICON_SIZE := Vector2(56, 56)
const DIR_ICONS: Dictionary = {
	TrickController.Dir.UP: preload("res://resources/img/Icons/xbox_stick_r_up.svg"),
	TrickController.Dir.DOWN: preload("res://resources/img/Icons/xbox_stick_r_down.svg"),
	TrickController.Dir.LEFT: preload("res://resources/img/Icons/xbox_stick_r_left.svg"),
	TrickController.Dir.RIGHT: preload("res://resources/img/Icons/xbox_stick_r_right.svg"),
}
const TAP_ICON := preload("res://resources/img/Icons/touch_tap.svg")
const DOUBLE_TAP_ICON := preload("res://resources/img/Icons/touch_tap_double.svg")
const HOLD_ICON := preload("res://resources/img/Icons/touch_tap_hold.svg")
const GESTURE_ICONS: Dictionary = {
	TrickController.Gesture.TAP: [TAP_ICON],
	TrickController.Gesture.DOUBLE_TAP: [DOUBLE_TAP_ICON],
	TrickController.Gesture.HOLD: [HOLD_ICON],
	TrickController.Gesture.DOUBLE_TAP_HOLD: [DOUBLE_TAP_ICON, HOLD_ICON],
}

@onready var tricks_grid: GridContainer = %TricksGrid
@onready var close_tricks_btn: Button = %CloseTricksBtn
@onready var bg_tint: ColorRect = %BGTint


func Enter(state_context: StateContext):
	return_ctx = state_context
	return_state = state_context.return_state

	if state_context is PauseStateContext:
		bg_tint.visible = state_context.show_bg_tint
	else:
		bg_tint.visible = false

	_build_grid()
	ui.show()

	close_tricks_btn.pressed.connect(_on_close_tricks_pressed)


func Exit(_state_context: StateContext):
	ui.hide()
	close_tricks_btn.pressed.disconnect(_on_close_tricks_pressed)


## One row per stick direction, one column per gesture.
func _build_grid():
	for child in tricks_grid.get_children():
		child.queue_free()

	var gestures := TrickController.Gesture.values()
	tricks_grid.columns = gestures.size() + 1

	_add_header("", [])
	for gesture in gestures:
		_add_header(TrickController.Gesture.keys()[gesture].capitalize(), GESTURE_ICONS[gesture])

	for dir in TrickController.Dir.values():
		_add_header(TrickController.Dir.keys()[dir].capitalize(), [DIR_ICONS[dir]])
		for gesture in gestures:
			_add_cell(_cell_text(gesture, dir))


## Tricks bound to this slot. A trick bound in every state shows bare; otherwise its states follow.
func _cell_text(gesture: int, dir: int) -> String:
	var states_by_trick: Dictionary = {}
	for state in TrickController.BINDINGS:
		var trick: int = TrickController.BINDINGS[state][gesture][dir]
		if trick == TrickController.Trick.NONE:
			continue
		if not states_by_trick.has(trick):
			states_by_trick[trick] = []
		states_by_trick[trick].append(TrickController.TrickState.keys()[state].capitalize())

	var lines: Array[String] = []
	for trick in states_by_trick:
		var trick_name := TrickController.trick_to_str(trick).capitalize()
		var states: Array = states_by_trick[trick]
		if states.size() == TrickController.BINDINGS.size():
			lines.append(trick_name)
		else:
			lines.append("%s (%s)" % [trick_name, ", ".join(states)])
	return "\n".join(lines)


## Gesture row / direction column: icons + the theme's TableHeaderLabel, centered.
func _add_header(text: String, icons: Array):
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	for icon in icons:
		var tex := TextureRect.new()
		tex.texture = icon
		tex.custom_minimum_size = HEADER_ICON_SIZE
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(tex)
	var label := Label.new()
	label.theme_type_variation = &"TableHeaderLabel"
	label.text = text
	box.add_child(label)
	tricks_grid.add_child(box)


## Empty slots show a dimmed "-".
func _add_cell(text: String):
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = text if text != "" else "-"
	if text == "":
		label.modulate.a = 0.3
	tricks_grid.add_child(label)


func _on_close_tricks_pressed():
	transitioned.emit(return_state, StateContext.NewWithReturn(self))


#override
func on_cancel_key_pressed():
	_on_close_tricks_pressed()
