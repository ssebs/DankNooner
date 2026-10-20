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


## Plays this sound at its authored level on `player`, for positional copies (horns, remote riders).
func play_on(player: AudioStreamPlayer3D) -> void:
	player.stream = stream
	player.volume_db = volume_db
	# Inverse-distance boosts gain inside unit_size; cap at the authored level
	player.max_db = volume_db
	player.play()


## Virtual hook for parameter-driven sounds (e.g. RPM → pitch). Override in subclasses.
func set_parameter(_param_name: String, _value: float) -> void:
	pass


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if stream == null:
		warnings.append("stream is null")
	return warnings
