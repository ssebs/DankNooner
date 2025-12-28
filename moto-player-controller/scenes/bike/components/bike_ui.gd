class_name BikeUI extends Node

@onready var gear_label: Label = null
@onready var speed_label: Label = null
@onready var throttle_bar: ProgressBar = null
@onready var brake_danger_bar: ProgressBar = null
@onready var difficulty_label: Label = null

# Shared state
var state: BikeState


func setup(bike_state: BikeState, gear: Label, spd: Label, throttle: ProgressBar, brake: ProgressBar, difficulty: Label):
	state = bike_state
	gear_label = gear
	speed_label = spd
	throttle_bar = throttle
	brake_danger_bar = brake
	difficulty_label = difficulty


func update_ui(input: BikeInput):
	_update_labels()
	_update_bars(input)
	_update_vibration()
	_update_difficulty_display()


func _update_labels():
	if !gear_label or !speed_label:
		return

	if state.is_stalled:
		gear_label.text = "STALLED\nGear: %d" % state.current_gear
	else:
		gear_label.text = "Gear: %d" % state.current_gear

	speed_label.text = "Speed: %d km/h" % int(state.speed * 3.6)


func _update_bars(input: BikeInput):
	if !throttle_bar or !brake_danger_bar:
		return

	throttle_bar.value = input.throttle

	var rpm_ratio = state.get_rpm_ratio()
	if rpm_ratio > 0.9:
		throttle_bar.modulate = Color(1.0, 0.2, 0.2) # Red at redline
	else:
		throttle_bar.modulate = Color(0.2, 0.8, 0.2) # Green

	brake_danger_bar.value = input.front_brake

	if state.brake_danger_level > 0.1:
		var danger_color = Color(1.0, 1.0 - state.brake_danger_level, 0.0)
		brake_danger_bar.modulate = danger_color
	else:
		brake_danger_bar.modulate = Color(0.3, 0.5, 0.9)


func _update_vibration():
	var weak_total = 0.0
	var strong_total = 0.0
	var _brake_vibe_intensity = 2.0

	# Brake danger vibration
	if state.brake_danger_level > 0.1:
		weak_total += state.brake_danger_level * _brake_vibe_intensity
		strong_total += state.brake_danger_level * state.brake_danger_level * _brake_vibe_intensity

	# Fishtail vibration
	var fishtail_intensity = abs(state.fishtail_angle) / state.max_fishtail_angle if state.max_fishtail_angle > 0 else 0.0
	if fishtail_intensity > 0.1:
		weak_total += fishtail_intensity * 0.6
		strong_total += fishtail_intensity * fishtail_intensity * 0.8

	# Apply vibration
	if weak_total > 0.01 or strong_total > 0.01:
		Input.start_joy_vibration(0, clamp(weak_total, 0.0, 1.0), clamp(strong_total, 0.0, 1.0), vibration_duration)
	else:
		stop_vibration()


func stop_vibration():
	Input.stop_joy_vibration(0)


func set_difficulty(easy: bool):
	state.is_easy_mode = easy
	_update_difficulty_display()


func _update_difficulty_display():
	if !difficulty_label:
		return
	if state.is_easy_mode:
		difficulty_label.text = "Easy"
		difficulty_label.modulate = Color(0.2, 0.8, 0.2)
	else:
		difficulty_label.text = "Hard"
		difficulty_label.modulate = Color(1.0, 0.3, 0.3)
