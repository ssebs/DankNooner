class_name BikeAudio extends Node

@onready var engine_sound: AudioStreamPlayer = null
@onready var tire_screech: AudioStreamPlayer = null

# Audio settings
@export var engine_min_pitch: float = 0.8
@export var engine_max_pitch: float = 1.6
@export var gear_grind_volume: float = 0.3
@export var stoppie_volume: float = 0.5
@export var fishtail_volume: float = 0.7

# External state (set by parent)
var speed: float = 0.0
var current_rpm: float = 0.0
var idle_rpm: float = 1000.0
var max_rpm: float = 8000.0
var is_stalled: bool = false


func setup(engine: AudioStreamPlayer, screech: AudioStreamPlayer):
	engine_sound = engine
	tire_screech = screech


func update_engine_audio(throttle: float):
	if !engine_sound:
		return
	
	if is_stalled:
		if engine_sound.playing:
			engine_sound.stop()
		return

	if speed > 0.5 or throttle > 0:
		if !engine_sound.playing:
			engine_sound.play()

		var rpm_ratio = (current_rpm - idle_rpm) / (max_rpm - idle_rpm)
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
	if !tire_screech:
		return
	tire_screech.volume_db = linear_to_db(gear_grind_volume)
	tire_screech.play()


func stop_engine():
	if !engine_sound:
		return
	if engine_sound.playing:
		engine_sound.stop()
