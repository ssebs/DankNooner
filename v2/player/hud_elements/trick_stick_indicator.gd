## Trick-stick readout left of the live combo score: the right stick as TrickController reads it, inside
## the dead zone it must leave to register a direction. Shown while trick is held, on any device; the
## mouse stick has no spring-back, so it's how a flick back to center gets judged there. Local and
## display-only; RidingHUDState drives it.
class_name TrickStickIndicator extends Control

const DOT_RADIUS: float = 4.0

var _stick := Vector2.ZERO


func set_stick(stick: Vector2) -> void:
	if stick == _stick:
		return
	_stick = stick
	queue_redraw()


func _draw():
	var center := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - DOT_RADIUS
	var threshold := -TrickController.TRICK_CAM_THRESHOLD
	draw_circle(center, r + DOT_RADIUS, Color(UtilsConstants.UI_GLASS, 0.6))
	draw_arc(center, r, 0.0, TAU, 32, UtilsConstants.UI_TRACK, 2.0, true)
	# Drawn round for readability; _stick_dir() actually compares the larger axis (a square).
	draw_arc(center, r * threshold, 0.0, TAU, 32, UtilsConstants.UI_TRACK, 1.0, true)
	var active := maxf(absf(_stick.x), absf(_stick.y)) >= threshold
	var dot_color := UtilsConstants.UI_BLUE if active else Color.WHITE
	draw_circle(center + Vector2(_stick.x, -_stick.y) * r, DOT_RADIUS, dot_color)
