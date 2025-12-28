class_name BikeUI extends Node

@onready var gear_label: Label = null
@onready var speed_label: Label = null
@onready var throttle_bar: ProgressBar = null
@onready var brake_danger_bar: ProgressBar = null

# Vibration settings
@export var vibration_duration: float = 0.15

# Component references
@onready var bike_physics: BikePhysics = %BikePhysics
@onready var bike_gearing: BikeGearing = %BikeGearing
@onready var bike_crash: BikeCrash = %BikeCrash
@onready var bike_tricks: BikeTricks = %BikeTricks


func setup(gear: Label, spd: Label, throttle: ProgressBar, brake: ProgressBar):
	gear_label = gear
	speed_label = spd
	throttle_bar = throttle
	brake_danger_bar = brake


func update_ui():
	_update_labels()
	_update_bars()
	_update_vibration()


func _update_labels():
	if !gear_label or !speed_label:
		return

	if bike_gearing.is_stalled:
		gear_label.text = "STALLED\nGear: %d" % bike_gearing.current_gear
	else:
		gear_label.text = "Gear: %d" % bike_gearing.current_gear

	speed_label.text = "Speed: %d km/h" % int(bike_physics.speed * 3.6)


func _update_bars():
	if !throttle_bar or !brake_danger_bar:
		return

	var throttle = Input.get_action_strength("throttle_pct")
	throttle_bar.value = throttle

	var rpm_ratio = (bike_gearing.current_rpm - bike_gearing.idle_rpm) / (bike_gearing.max_rpm - bike_gearing.idle_rpm)
	if rpm_ratio > 0.9:
		throttle_bar.modulate = Color(1.0, 0.2, 0.2) # Red at redline
	else:
		throttle_bar.modulate = Color(0.2, 0.8, 0.2) # Green

	var front_brake = Input.get_action_strength("brake_front_pct")
	brake_danger_bar.value = front_brake

	if bike_crash.brake_danger_level > 0.1:
		var danger_color = Color(1.0, 1.0 - bike_crash.brake_danger_level, 0.0)
		brake_danger_bar.modulate = danger_color
	else:
		brake_danger_bar.modulate = Color(0.3, 0.5, 0.9)


func _update_vibration():
	var weak_total = 0.0
	var strong_total = 0.0
	var _brake_vibe_intensity = 2.0

	# Brake danger vibration
	if bike_crash.brake_danger_level > 0.1:
		weak_total += bike_crash.brake_danger_level * _brake_vibe_intensity
		strong_total += bike_crash.brake_danger_level * bike_crash.brake_danger_level * _brake_vibe_intensity

	# Fishtail vibration
	var fishtail_intensity = abs(bike_tricks.fishtail_angle) / bike_tricks.max_fishtail_angle
	if fishtail_intensity > 0.1:
		weak_total += fishtail_intensity * 0.6
		strong_total += fishtail_intensity * fishtail_intensity * 0.8

	# Redline vibration
	var rpm_ratio = (bike_gearing.current_rpm - bike_gearing.idle_rpm) / (bike_gearing.max_rpm - bike_gearing.idle_rpm)
	if rpm_ratio > 0.85 and !bike_gearing.is_stalled:
		var redline_intensity = (rpm_ratio - 0.85) / 0.15
		weak_total += redline_intensity * 0.4
		strong_total += redline_intensity * 0.2

	# Apply vibration
	if weak_total > 0.01 or strong_total > 0.01:
		Input.start_joy_vibration(0, clamp(weak_total, 0.0, 1.0), clamp(strong_total, 0.0, 1.0), vibration_duration)
	else:
		stop_vibration()


func stop_vibration():
	Input.stop_joy_vibration(0)
