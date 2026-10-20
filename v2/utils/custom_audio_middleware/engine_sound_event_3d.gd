@tool
## Positional copy of an AudioManager EngineSoundEvent, so other riders can be heard going by.
## Plays the template's streams at its authored levels; the pitch/crossfade math is EngineSoundEvent's.
class_name EngineSoundEvent3D extends AudioStreamPlayer3D

@export var high_layer: AudioStreamPlayer3D

var _template: EngineSoundEvent
var _bike_def: BikeSkinDefinition


func play_engine(template: EngineSoundEvent, bike_def: BikeSkinDefinition) -> void:
	_template = template
	_bike_def = bike_def
	stream = template.stream
	volume_db = template.base_volume_db
	# Inverse-distance boosts gain inside unit_size; cap at the authored level
	max_db = volume_db
	play()
	if template.high_layer:
		high_layer.stream = template.high_layer.stream
		high_layer.play()
	else:
		high_layer.stop()


func stop_engine() -> void:
	stop()
	high_layer.stop()


func set_rpm(value: float) -> void:
	var rpm: float = clampf(value, 0.0, 1.0)
	pitch_scale = EngineSoundEvent.rpm_to_pitch(
		rpm, _bike_def.engine_rpm_pitch_curve, _bike_def.engine_min_pitch, _bike_def.engine_max_pitch
	)
	if _template.high_layer == null:
		return
	high_layer.pitch_scale = pitch_scale
	var gains := EngineSoundEvent.crossfade_db(rpm, _bike_def.engine_blend_curve)
	volume_db = _template.base_volume_db + gains.x
	high_layer.volume_db = _template.base_high_volume_db + gains.y
	max_db = volume_db
	high_layer.max_db = high_layer.volume_db


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if high_layer == null:
		warnings.append("high_layer is null")
	return warnings
