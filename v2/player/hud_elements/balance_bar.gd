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
@export var prog_width_pct: float = 8
@export var smooth_speed: float = 12.0

const COLOR_COOL: Color = Color(0.6, 0.85, 1.0)  # light blue — in balance point
const COLOR_WARM: Color = Color(1.0, 0.65, 0.15)  # orange — drifting out
const COLOR_HOT: Color = Color(1.0, 0.15, 0.1)  # red — about to crash
const WARN_MARKER_COLOR := Color(1, 1, 1, 0.08)

@onready var tex_bar: TextureProgressBar = %TexBar
@onready var low_warn_bar: ColorRect = %LowWarnBar
@onready var high_warn_bar: ColorRect = %HighWarnBar

var _max_offset_px := 212.0
var _target_offset := Vector2.ZERO
var _target_tint := COLOR_COOL


func _ready():
	tex_bar.value = prog_width_pct
	update_warn_markers()


func _process(delta: float):
	tex_bar.texture_progress_offset = tex_bar.texture_progress_offset.lerp(
		_target_offset, 1.0 - exp(-smooth_speed * delta)
	)
	tex_bar.tint_progress = tex_bar.tint_progress.lerp(
		_target_tint, 1.0 - exp(-smooth_speed * delta)
	)


func _update_bar():
	# Remap so the balance point center sits at the middle of the bar
	var bp_center := (warn_low_val + warn_high_val) / 2.0
	var t: float = (current_val - bp_center) / (max_val - min_val) + 0.5
	var offset_x: float = lerp(-_max_offset_px, _max_offset_px, t)
	_target_offset = Vector2(offset_x, 0)

	# Heat-based tint: cool in balance point, orange drifting out, red near crash
	var center := (warn_low_val + warn_high_val) / 2.0
	var safe_half := (warn_high_val - warn_low_val) / 2.0
	var dist_from_center := absf(current_val - center)
	# 0 = dead center, 1 = at warn boundary, >1 = in danger zone
	var heat := clampf(dist_from_center / safe_half, 0.0, 2.0)
	if heat <= 1.0:
		_target_tint = COLOR_COOL.lerp(COLOR_WARM, heat)
	else:
		_target_tint = COLOR_WARM.lerp(COLOR_HOT, heat - 1.0)


func update_warn_markers():
	var bar_width := tex_bar.size.x
	var bar_height := tex_bar.size.y
	var bp_center := (warn_low_val + warn_high_val) / 2.0
	var range_size := max_val - min_val

	var t_low := (warn_low_val - bp_center) / range_size + 0.5
	low_warn_bar.position.x = 0.0
	low_warn_bar.size = Vector2(t_low * bar_width, bar_height)
	low_warn_bar.color = WARN_MARKER_COLOR

	var t_high := (warn_high_val - bp_center) / range_size + 0.5
	high_warn_bar.position.x = t_high * bar_width
	high_warn_bar.size = Vector2((1.0 - t_high) * bar_width, bar_height)
	high_warn_bar.color = WARN_MARKER_COLOR
