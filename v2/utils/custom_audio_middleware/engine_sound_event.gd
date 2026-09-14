@tool
class_name EngineSoundEvent extends SoundEvent

## Optional second clip. When set, this node is the low-RPM layer and equal-power
## crossfades into `high_layer` as RPM rises (both share the pitch curve below).
@export var high_layer: AudioStreamPlayer
## Logs the per-tick crossfade state (rpm/pitch/gains/volumes/playing) to the console.
@export var debug_verbose: bool = false

## RPM [0..1] → interpolation factor [0..1] between min_pitch and max_pitch.
## Set by AudioManager.play_revs() from the active BikeSkinDefinition.
var rpm_curve: Curve
var min_pitch: float = 1.0
var max_pitch: float = 2.828
## RPM [0..1] → crossfade position [0..1]. Null = linear. Set by play_revs().
var blend_curve: Curve
## Authored volumes, captured so the crossfade offsets from them instead of clobbering.
var _base_volume_db: float
var _base_high_volume_db: float


func _ready() -> void:
	super()
	_base_volume_db = volume_db
	if high_layer:
		_base_high_volume_db = high_layer.volume_db
	if Engine.is_editor_hint():
		return
	# Same dup-and-loop the base stream gets in SoundEvent, for the high layer.
	if high_layer and high_layer.stream and "loop" in high_layer.stream:
		high_layer.stream = high_layer.stream.duplicate()
		high_layer.stream.loop = true


# Named to avoid shadowing AudioStreamPlayer.play/stop — a native override isn't dispatched
# through a statically-typed EngineSoundEvent call, so the high layer would never start.
func play_engine() -> void:
	play()
	if high_layer:
		high_layer.play()


func stop_engine() -> void:
	stop()
	if high_layer:
		high_layer.stop()


func set_parameter(param_name: String, value: float) -> void:
	if param_name != "RPM":
		return
	var rpm: float = clampf(value, 0.0, 1.0)
	pitch_scale = lerpf(min_pitch, max_pitch, rpm_curve.sample(rpm))
	if high_layer == null:
		return
	high_layer.pitch_scale = pitch_scale
	# Equal-power crossfade: gains trace the sin/cos curves, keeping RMS constant.
	var t: float = blend_curve.sample(rpm) if blend_curve else rpm
	var low_gain: float = cos(t * PI / 2.0)
	var high_gain: float = sin(t * PI / 2.0)
	volume_db = _base_volume_db + _gain_db(low_gain)
	high_layer.volume_db = _base_high_volume_db + _gain_db(high_gain)
	DebugUtils.DebugMsg(
		(
			"engine blend: rpm=%.2f t=%.2f pitch=%.2f | low g=%.2f %.1fdB play=%s | high g=%.2f %.1fdB play=%s"
			% [
				rpm, t, pitch_scale,
				low_gain, volume_db, playing,
				high_gain, high_layer.volume_db, high_layer.playing,
			]
		),
		OS.has_feature("debug") and debug_verbose
	)


## Linear gain [0..1] → dB, floored so a fully-faded layer is silent without -inf.
func _gain_db(gain: float) -> float:
	return maxf(linear_to_db(gain), -80.0)
