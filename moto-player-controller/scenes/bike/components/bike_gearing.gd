class_name BikeGearing extends Node

signal gear_changed(new_gear: int)
signal engine_stalled
signal engine_started
signal gear_grind # Tried to shift without clutch

# Gear system
@export var num_gears: int = 6
@export var max_rpm: float = 8000.0
@export var idle_rpm: float = 1000.0
@export var stall_rpm: float = 500.0
@export var gear_ratios: Array[float] = [2.8, 1.9, 1.4, 1.1, 0.95, 0.8]

# State
var current_gear: int = 1
var current_rpm: float = 0.0
var is_stalled: bool = false
var clutch_value: float = 0.0

const CLUTCH_SPEED: float = 12.0

# External state (set by parent)
var speed: float = 0.0
var max_speed: float = 60.0


func _physics_process(delta):
	update_clutch(delta)


func update_clutch(delta):
	var clutch_input = Input.get_action_strength("clutch")
	clutch_value = move_toward(clutch_value, clutch_input, CLUTCH_SPEED * delta)

# Checks input for changing gears
# Emits gear_changed(current_gear) or gear_grind() depending on clutch_value
func handle_gear_shifting():
	if Input.is_action_just_pressed("gear_up"):
		if clutch_value > 0.5:
			if current_gear < num_gears:
				current_gear += 1
				gear_changed.emit(current_gear)
		else:
			gear_grind.emit()
	elif Input.is_action_just_pressed("gear_down"):
		if clutch_value > 0.5:
			if current_gear > 1:
				current_gear -= 1
				gear_changed.emit(current_gear)
		else:
			gear_grind.emit()


func get_max_speed_for_gear(gear: int = -1) -> float:
	if gear == -1:
		gear = current_gear
	var gear_ratio = gear_ratios[gear - 1]
	var lowest_ratio = gear_ratios[num_gears - 1]
	return max_speed * (lowest_ratio / gear_ratio)


func update_rpm(throttle: float):
	if is_stalled:
		current_rpm = 0.0
		# Restart engine with throttle + clutch while stalled
		if clutch_value > 0.5 and throttle > 0.3:
			is_stalled = false
			current_rpm = idle_rpm
			engine_started.emit()
		return

	# Calculate free-rev RPM (throttle controls directly when clutch in)
	var free_rev_rpm = lerpf(idle_rpm, max_rpm, throttle)

	# Calculate engaged RPM (locked to wheel speed)
	var gear_max_speed = get_max_speed_for_gear()
	var speed_ratio = speed / gear_max_speed if gear_max_speed > 0 else 0.0
	var engaged_rpm = lerpf(idle_rpm, max_rpm, clamp(speed_ratio, 0.0, 1.0))

	# Blend between free-rev and engaged based on clutch position
	var target_rpm = lerpf(engaged_rpm, free_rev_rpm, clutch_value)

	# Smooth RPM transitions (faster when free revving)
	var rpm_lerp_speed = lerpf(0.1, 0.25, clutch_value)
	current_rpm = lerpf(current_rpm, target_rpm, rpm_lerp_speed)

	# Clamp RPM
	current_rpm = clamp(current_rpm, idle_rpm, max_rpm)

	# Check for stall
	if clutch_value < 0.3 and current_rpm < stall_rpm and speed < 1.0:
		is_stalled = true
		current_gear = 1
		engine_stalled.emit()


func get_rpm_ratio() -> float:
	return (current_rpm - idle_rpm) / (max_rpm - idle_rpm)


func get_power_output(throttle: float) -> float:
	"""Returns power multiplier based on current RPM and gear"""
	if is_stalled:
		return 0.0

	var engagement = 1.0 - clutch_value
	if engagement < 0.1:
		return 0.0

	var rpm_ratio = get_rpm_ratio()
	var power_curve = rpm_ratio * (2.0 - rpm_ratio) # Peaks around 75% RPM

	var gear_ratio = gear_ratios[current_gear - 1]
	var base_ratio = gear_ratios[num_gears - 1]
	var torque_multiplier = gear_ratio / base_ratio

	return throttle * power_curve * torque_multiplier * engagement


func is_clutch_dump(last_clutch: float, throttle: float) -> bool:
	"""Returns true if clutch was just dumped while revving"""
	return last_clutch > 0.7 and clutch_value < 0.3 and throttle > 0.5


func reset():
	current_gear = 1
	current_rpm = idle_rpm
	is_stalled = false
	clutch_value = 0.0
