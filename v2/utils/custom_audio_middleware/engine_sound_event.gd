@tool
class_name EngineSoundEvent extends SoundEvent

## Maps RPM in [0..1] to pitch shift in semitones. If null at runtime, a default
## curve is built matching the FMOD project: (0, 0), (0.2, 2), (1.0, 18).
@export var rpm_to_semitones: Curve


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	if rpm_to_semitones == null:
		rpm_to_semitones = _build_default_rpm_curve()


func set_parameter(param_name: String, value: float) -> void:
	if param_name != "RPM":
		return
	var semitones: float = rpm_to_semitones.sample(clampf(value, 0.0, 1.0))
	pitch_scale = pow(2.0, semitones / 12.0)


func _build_default_rpm_curve() -> Curve:
	var c := Curve.new()
	c.min_value = 0.0
	c.max_value = 24.0
	c.add_point(Vector2(0.0, 0.0))
	c.add_point(Vector2(0.2, 2.0))
	c.add_point(Vector2(1.0, 18.0))
	return c
