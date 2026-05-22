@tool
class_name EngineSoundEvent extends SoundEvent

## RPM [0..1] → interpolation factor [0..1] between min_pitch and max_pitch.
## Set by AudioManager.play_revs() from the active BikeSkinDefinition.
var rpm_curve: Curve
var min_pitch: float = 1.0
var max_pitch: float = 2.828


func set_parameter(param_name: String, value: float) -> void:
	if param_name != "RPM":
		return
	var t: float = rpm_curve.sample(clampf(value, 0.0, 1.0))
	pitch_scale = lerpf(min_pitch, max_pitch, t)
