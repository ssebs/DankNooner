class_name BikeAudio extends Node

@onready var engine_sound: AudioStreamPlayer = null
@onready var tire_screech: AudioStreamPlayer = null
@onready var engine_grind: AudioStreamPlayer = null

# Audio settings
@export var engine_min_pitch: float = 0.44
@export var engine_max_pitch: float = 1.6
@export var gear_grind_volume: float = 0.3
@export var stoppie_volume: float = 0.4
@export var fishtail_volume: float = 0.4

# Shared state
var state: BikeState


func setup(bike_state: BikeState, engine: AudioStreamPlayer, screech: AudioStreamPlayer, grind: AudioStreamPlayer):
	state = bike_state
	engine_sound = engine
	tire_screech = screech
	engine_grind = grind


func update_engine_audio(input: BikeInput, rpm_ratio: float):
	if !engine_sound:
		return

	if state.is_stalled:
		if engine_sound.playing:
			engine_sound.stop()
		return

	if state.speed > 0.5 or input.throttle > 0:
		if !engine_sound.playing:
			engine_sound.play()

		var target_pitch = lerpf(engine_min_pitch, engine_max_pitch, clamp(rpm_ratio, 0.0, 1.0))
		engine_sound.pitch_scale = target_pitch
	else:
		if engine_sound.playing:
			engine_sound.stop()


func play_tire_screech(volume: float):
	if !tire_screech:
		return
	if !tire_screech.playing:
		tire_screech.volume_db = linear_to_db(volume)
		tire_screech.play()


func stop_tire_screech():
	if !tire_screech:
		return
	if tire_screech.playing:
		tire_screech.stop()


func play_gear_grind():
	if !engine_grind:
		return
	engine_grind.volume_db = linear_to_db(gear_grind_volume)
	engine_grind.play()


func stop_engine():
	if !engine_sound:
		return
	if engine_sound.playing:
		engine_sound.stop()
