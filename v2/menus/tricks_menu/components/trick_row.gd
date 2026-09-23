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
## Drops the fixed column widths so the row fits narrow spots (HUD).
@export var compact: bool = false
## Shows which TrickState the stick input applies in (HUD; the menu's tab already says it).
@export var show_state: bool = false

const DIR_ICONS: Dictionary = {
	TrickController.Dir.UP: preload("res://resources/img/Icons/xbox_stick_r_up.svg"),
	TrickController.Dir.DOWN: preload("res://resources/img/Icons/xbox_stick_r_down.svg"),
	TrickController.Dir.LEFT: preload("res://resources/img/Icons/xbox_stick_r_left.svg"),
	TrickController.Dir.RIGHT: preload("res://resources/img/Icons/xbox_stick_r_right.svg"),
}
const COMPACT_HOWTO_WIDTH := 260

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

## Save-safe id of what this row shows: "STATE/TRICK/GESTURE/DIR" for stick tricks, "TRICK" for
## how-tos.
var pin: String = ""


func _ready() -> void:
	pin_btn.visible = pinnable
	if compact:
		columns.add_theme_constant_override("separation", 12)
		for col: Control in [dir_box, gesture_col, score_label]:
			col.custom_minimum_size.x = 0
		howto_label.custom_minimum_size.x = COMPACT_HOWTO_WIDTH
	if Engine.is_editor_hint():
		return
	pin_btn.pressed.connect(func(): pin_pressed.emit(pin))


## Right-stick trick from TrickController.BINDINGS[state][gesture][dir].
func populate_stick(state: int, trick: TrickController.Trick, gesture: int, dir: int) -> void:
	var state_name: String = TrickController.TrickState.keys()[state]
	var gesture_name: String = TrickController.Gesture.keys()[gesture]
	var dir_name: String = TrickController.Dir.keys()[dir]
	_populate(trick)
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
	state_label.hide()
	stick_input.hide()
	howto_label.show()
	howto_label.text = "TRICK_HOWTO_" + pin


## Shows the first BINDINGS slot for the trick, else its how-to.
func populate_trick(trick: TrickController.Trick) -> void:
	for state in TrickController.BINDINGS:
		for gesture in TrickController.BINDINGS[state]:
			var dir: int = TrickController.BINDINGS[state][gesture].find(trick)
			if dir != -1:
				populate_stick(state, trick, gesture, dir)
				return
	populate_howto(trick)


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


func set_pinned(pinned: bool) -> void:
	pin_btn.set_pressed_no_signal(pinned)
	pin_btn.text = "PINNED_LABEL" if pinned else "PIN_TRICK_LABEL"


func _populate(trick: TrickController.Trick) -> void:
	name_label.text = TrickController.trick_to_str(trick).capitalize()
	if TrickController.HELD_TRICK_SCORE.has(trick):
		score_label.text = "+%s/s" % TrickController.HELD_TRICK_SCORE[trick]
	else:
		score_label.text = "+%s" % TrickController.ONE_TIME_TRICK_SCORE[trick]
