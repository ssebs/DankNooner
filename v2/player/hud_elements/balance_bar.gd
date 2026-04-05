@tool
class_name BalanceBar extends Control

#
#  [@@@^XX^@@@]
#
@export var current_val: float = 5:
	set(val):
		if current_val != val:
			current_val = val
			_update_bar()

@export var min_val: float = 0
@export var max_val: float = 10
@export var warn_low_val: float = 3
@export var warn_high_val: float = 7
@export var prog_width_pct: float = 16
const WARN_COLOR: Color = Color.RED
const SAFE_COLOR: Color = Color.WHITE

@onready var tex_bar: TextureProgressBar = %TexBar

var _max_offset_px := 212.0


func _ready():
	tex_bar.value = prog_width_pct


func _update_bar():
	# set position using current val lerping from -_max_offset_px to _max_offset_px
	var t: float = (current_val - min_val) / (max_val - min_val)
	var offset_x: float = lerp(-_max_offset_px, _max_offset_px, t)
	tex_bar.texture_progress_offset = Vector2(offset_x, 0)

	# Tint red when outside the warn range (in the danger zones)
	var in_danger: bool = current_val < warn_low_val or current_val > warn_high_val
	tex_bar.tint_over = WARN_COLOR if in_danger else SAFE_COLOR
