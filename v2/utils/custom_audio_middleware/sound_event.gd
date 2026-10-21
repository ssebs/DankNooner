@tool
class_name SoundEvent extends AudioStreamPlayer

## When true, the stream is duplicated and `loop` is set on the copy so the
## shared resource isn't mutated. Subclasses inherit this behavior.
@export var loop: bool = false

## Authored volume, captured so fades and crossfades offset from it instead of clobbering.
var base_volume_db: float
var _fade: Tween


func _ready() -> void:
	base_volume_db = volume_db
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


## Plays from silence, rising to the authored level over `duration`.
func fade_in(duration: float) -> void:
	_restart_fade()
	volume_linear = 0.0
	stream_paused = false
	play()
	_fade.tween_property(self, "volume_linear", db_to_linear(base_volume_db), duration)


## Falls to silence over `duration`, then stops back at the authored level, unpaused.
func fade_out(duration: float) -> void:
	_restart_fade()
	_fade.tween_property(self, "volume_linear", 0.0, duration)
	_fade.tween_callback(_stop_at_base_volume)


func _restart_fade() -> void:
	if _fade:
		_fade.kill()
	_fade = create_tween()


func _stop_at_base_volume() -> void:
	stop()
	volume_db = base_volume_db
	stream_paused = false


## Virtual hook for parameter-driven sounds (e.g. RPM → pitch). Override in subclasses.
func set_parameter(_param_name: String, _value: float) -> void:
	pass


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if stream == null:
		warnings.append("stream is null")
	return warnings
