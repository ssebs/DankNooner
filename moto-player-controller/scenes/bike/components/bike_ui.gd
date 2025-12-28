class_name BikeUI extends Node

@onready var gear_label: Label = null
@onready var speed_label: Label = null
@onready var throttle_bar: ProgressBar = null
@onready var brake_danger_bar: ProgressBar = null

# Vibration settings
@export var vibration_duration: float = 0.15

# External state (set by parent)
var current_gear: int = 1
var speed: float = 0.0
var current_rpm: float = 0.0
var idle_rpm: float = 1000.0
var max_rpm: float = 8000.0
var is_stalled: bool = false
var brake_danger_level: float = 0.0
var fishtail_angle: float = 0.0
var max_fishtail_angle: float = deg_to_rad(90)


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
	if not gear_label or not speed_label:
		return

	if is_stalled:
		gear_label.text = "STALLED"
	else:
		gear_label.text = "Gear: %d" % current_gear

	speed_label.text = "Speed: %d km/h" % int(speed * 3.6)


func _update_bars():
	if not throttle_bar or not brake_danger_bar:
		return

	var throttle = Input.get_action_strength("throttle_pct")
	throttle_bar.value = throttle

	var rpm_ratio = (current_rpm - idle_rpm) / (max_rpm - idle_rpm)
	if rpm_ratio > 0.9:
		throttle_bar.modulate = Color(1.0, 0.2, 0.2)  # Red at redline
	else:
		throttle_bar.modulate = Color(0.2, 0.8, 0.2)  # Green

	var front_brake = Input.get_action_strength("brake_front_pct")
	brake_danger_bar.value = front_brake

	if brake_danger_level > 0.1:
		var danger_color = Color(1.0, 1.0 - brake_danger_level, 0.0)
		brake_danger_bar.modulate = danger_color
	else:
		brake_danger_bar.modulate = Color(0.3, 0.5, 0.9)


func _update_vibration():
	var weak_total = 0.0
	var strong_total = 0.0

	# Brake danger vibration
	if brake_danger_level > 0.1:
		weak_total += brake_danger_level * 1.0
		strong_total += brake_danger_level * brake_danger_level * 1.0

	# Fishtail vibration
	var fishtail_intensity = abs(fishtail_angle) / max_fishtail_angle
	if fishtail_intensity > 0.1:
		weak_total += fishtail_intensity * 0.6
		strong_total += fishtail_intensity * fishtail_intensity * 0.8

	# Redline vibration
	var rpm_ratio = (current_rpm - idle_rpm) / (max_rpm - idle_rpm)
	if rpm_ratio > 0.85 and not is_stalled:
		var redline_intensity = (rpm_ratio - 0.85) / 0.15
		weak_total += redline_intensity * 0.4
		strong_total += redline_intensity * 0.2

	# Apply vibration
	if weak_total > 0.01 or strong_total > 0.01:
		Input.start_joy_vibration(0, clamp(weak_total, 0.0, 1.0), clamp(strong_total, 0.0, 1.0), vibration_duration)
	else:
		Input.stop_joy_vibration(0)


func stop_vibration():
	Input.stop_joy_vibration(0)
