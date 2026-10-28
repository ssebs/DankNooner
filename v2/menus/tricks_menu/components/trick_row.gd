@tool
## One trick: name, how to do it (stick input or how-to text) and its score.
## Used in the tricks menu and for the pinned trick on the riding HUD.
class_name TrickRow extends PanelContainer

signal pin_pressed(pin: String)

## Shows the pin button (tricks menu); off for display-only rows (HUD).
@export var pinnable: bool = false:
	set(value):
		pinnable = value
		if is_node_ready():
			pin_btn.visible = value
## HUD: reads like the action hints, input key cap first, then the trick and its state, with no
## fixed column widths or score.
@export var compact: bool = false
## Shows which TrickState the stick input applies in (HUD; the menu's tab already says it).
@export var show_state: bool = false

const DIR_ICONS: Dictionary = {
	TrickController.Dir.UP: preload("res://resources/img/Icons/xbox_stick_r_up.svg"),
	TrickController.Dir.DOWN: preload("res://resources/img/Icons/xbox_stick_r_down.svg"),
	TrickController.Dir.LEFT: preload("res://resources/img/Icons/xbox_stick_r_left.svg"),
	TrickController.Dir.RIGHT: preload("res://resources/img/Icons/xbox_stick_r_right.svg"),
}

@onready var columns: HBoxContainer = %Columns
@onready var name_label: Label = %NameLabel
@onready var state_label: Label = %StateLabel
@onready var stick_input: HBoxContainer = %StickInput
@onready var dir_box: HBoxContainer = %DirBox
@onready var dir_icon: TextureRect = %DirIcon
@onready var dir_label: Label = %DirLabel
@onready var gesture_col: CenterContainer = %GestureCol
@onready var gesture_chip: Label = %GestureChip
@onready var howto_label: Label = %HowtoLabel
@onready var score_label: Label = %ScoreLabel
@onready var pin_btn: Button = %PinBtn
## Tricks menu over the TrickDemo: plays this trick there. Hidden elsewhere.
@onready var show_btn: Button = %ShowBtn

## Save-safe id of what this row shows: "STATE/TRICK/GESTURE/DIR" for stick tricks, "TRICK" for
## how-tos.
var pin: String = ""
var trick_type: TrickController.Trick = TrickController.Trick.NONE
## Stick rows' TrickController.Dir; NO_DIR for how-to rows.
var _dir: int = TrickController.NO_DIR


func _ready() -> void:
	pin_btn.visible = pinnable
	if compact:
		columns.add_theme_constant_override("separation", 8)
		for col: Control in [dir_box, gesture_col]:
			col.custom_minimum_size.x = 0
		columns.move_child(stick_input, 0)
		score_label.hide()
		dir_label.theme_type_variation = &"GestureChipLabel"
		# Only the key is a cap; a boxed gesture reads as a button to press.
		gesture_chip.theme_type_variation = &"DimLabel"
		for label: Label in [dir_label, gesture_chip, state_label]:
			label.add_theme_font_size_override("font_size", 16)
	if Engine.is_editor_hint():
		return
	pin_btn.pressed.connect(func(): pin_pressed.emit(pin))


## Right-stick trick from TrickController.BINDINGS[state][gesture][dir].
func populate_stick(state: int, trick: TrickController.Trick, gesture: int, dir: int) -> void:
	var state_name: String = TrickController.TrickState.keys()[state]
	var gesture_name: String = TrickController.Gesture.keys()[gesture]
	var dir_name: String = TrickController.Dir.keys()[dir]
	_populate(trick)
	_dir = dir
	pin = "/".join([state_name, TrickController.trick_to_str(trick), gesture_name, dir_name])
	state_label.visible = show_state
	state_label.text = state_name.capitalize()
	stick_input.show()
	howto_label.hide()
	dir_icon.texture = DIR_ICONS[dir]
	dir_label.text = "TRICK_DIR_" + dir_name
	gesture_chip.text = "TRICK_GESTURE_" + gesture_name


## Physics-driven trick; needs a TRICK_HOWTO_<NAME> localization key.
func populate_howto(trick: TrickController.Trick) -> void:
	_populate(trick)
	pin = TrickController.trick_to_str(trick)
	stick_input.hide()
	var howto := "TRICK_HOWTO_" + pin
	# Compact (HUD): rides the name's subtitle line like a stick row's state, instead of a wrapped column.
	state_label.visible = compact
	state_label.text = howto
	howto_label.visible = !compact
	howto_label.text = howto


## Rebuild a row from its pin id (see `pin`).
func populate_pin(pin_id: String) -> void:
	var parts := pin_id.split("/")
	if parts.size() == 1:
		populate_howto(TrickController.str_to_trick(parts[0]))
		return
	populate_stick(
		TrickController.TrickState[parts[0]],
		TrickController.str_to_trick(parts[1]),
		TrickController.Gesture[parts[2]],
		TrickController.Dir[parts[3]]
	)


## HUD: off a pad, show the key the stick direction's cam_* action is bound to instead.
func set_gamepad(gamepad: bool) -> void:
	# How-to rows have no stick input.
	if _dir == TrickController.NO_DIR:
		return
	var dir_name: String = TrickController.Dir.keys()[_dir]
	var event := ControlBindings.event_for("cam_" + dir_name.to_lower(), false)
	# Unbound key: fall back to the stick, which still works.
	var use_key := not gamepad and event != null
	dir_icon.visible = not use_key
	# Compact: the stick glyph already says the direction.
	dir_label.visible = use_key or not compact
	dir_label.text = ControlBindings.event_text(event) if use_key else "TRICK_DIR_" + dir_name


func set_pinned(pinned: bool) -> void:
	pin_btn.set_pressed_no_signal(pinned)
	pin_btn.text = "PINNED_LABEL" if pinned else "PIN_TRICK_LABEL"


func _populate(trick: TrickController.Trick) -> void:
	trick_type = trick
	name_label.text = TrickController.trick_to_str(trick).capitalize()
	if TrickController.HELD_TRICK_SCORE.has(trick):
		score_label.text = "+%s/s" % TrickController.HELD_TRICK_SCORE[trick]
	else:
		score_label.text = "+%s" % TrickController.ONE_TIME_TRICK_SCORE[trick]
