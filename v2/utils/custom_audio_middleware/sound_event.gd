@tool
class_name SoundEvent extends AudioStreamPlayer

## When true, the stream is duplicated and `loop` is set on the copy so the
## shared resource isn't mutated. Subclasses inherit this behavior.
@export var loop: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if loop and stream and "loop" in stream:
		stream = stream.duplicate()
		stream.loop = true


## Virtual hook for parameter-driven sounds (e.g. RPM → pitch). Override in subclasses.
func set_parameter(_param_name: String, _value: float) -> void:
	pass


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if stream == null:
		warnings.append("stream is null")
	return warnings
