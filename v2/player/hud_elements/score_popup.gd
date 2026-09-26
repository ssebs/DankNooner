@tool
## Borderlands-style "+340" popup when a combo banks: pops small -> big, then drifts up-right
## with a slight tilt and fades. Tinted with the ComboCounter tier color for the combo's
## multiplier. Each pop is its own Label, so rapid banks stack instead of resetting.
class_name ScorePopup extends Control

const FONT_SIZE: int = 56
const OUTLINE_SIZE: int = 12
const POP_SECS: float = 0.2
const POP_START_SCALE: float = 0.3
const POP_PEAK_SCALE: float = 1.3
const DRIFT_SECS: float = 1.0
const DRIFT_PX := Vector2(90.0, -110.0)
## Max tilt either way (radians); the sign is random per pop.
const TILT_RAD: float = 0.25
const FADE_SECS: float = 0.4


func pop(points: int, multiplier: int) -> void:
	var label := Label.new()
	label.text = "+%d" % points
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	var tiers := ComboCounter.TIER_COLORS
	label.modulate = tiers[mini(multiplier - 1, tiers.size() - 1)]
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	# Centered on this control, scaling/rotating about its own middle.
	label.reset_size()
	label.pivot_offset = label.size / 2.0
	label.position = size / 2.0 - label.size / 2.0
	label.scale = Vector2.ONE * POP_START_SCALE

	var tween := label.create_tween()
	var grow := tween.tween_property(label, "scale", Vector2.ONE * POP_PEAK_SCALE, POP_SECS)
	grow.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Drift, tilt and fade run together once the pop lands.
	tween.set_parallel()
	tween.chain().tween_property(label, "position", label.position + DRIFT_PX, DRIFT_SECS)
	tween.tween_property(label, "rotation", TILT_RAD * signf(randf() - 0.5), DRIFT_SECS)
	tween.tween_property(label, "modulate:a", 0.0, FADE_SECS).set_delay(DRIFT_SECS - FADE_SECS)
	tween.chain().tween_callback(label.queue_free)
