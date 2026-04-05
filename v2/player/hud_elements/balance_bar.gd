@tool
class_name BalanceBar extends TextureProgressBar

#
#  [@@@^XX^@@@]
#
@export var current_val: float = 5:
	set(val):
		current_val = val
		_update_bar()

@export var min_val: float = 0
@export var max_val: float = 10
@export var warn_low_val: float = 3
@export var warn_high_val: float = 7
@export var prog_width_pct: float = 16

# TODO: tint the over/under when outside a warning val

var _max_offset_px := 212.0


func _ready():
	self.value = prog_width_pct / 100


func _update_bar():
	# set position using current val lerping from -_max_offset_px to _max_offset_px
	# self.texture_progress_offset =
	pass
