class_name BikeGearing extends Node

signal gear_changed(new_gear: int)
signal engine_stalled
signal engine_started
signal gear_grind # Tried to shift without clutch

# Gear system
@export var num_gears: int = 6
@export var max_rpm: float = 9000.0
@export var idle_rpm: float = 1000.0
@export var stall_rpm: float = 500.0
@export var gear_ratios: Array[float] = [2.8, 1.9, 1.4, 1.1, 0.95, 0.8]
@export var dont_require_clutch: bool = false

# Clutch tuning
@export var clutch_speed: float = 15.0
@export var friction_zone_start: float = 0.3  # Clutch starts engaging here
@export var friction_zone_end: float = 0.7    # Clutch fully engaged here
@export var gear_shift_threshold: float = 0.3 # Clutch value needed to shift (lower = faster shifts)

# Shared state
var state: BikeState

# Local state
var current_gear: int = 1
var current_rpm: float = 0.0
var is_stalled: bool = false
var clutch_value: float = 0.0


func setup(bike_state: BikeState):
	state = bike_state
	state.idle_rpm = idle_rpm
	state.max_rpm = max_rpm


func sync_to_state():
	state.current_gear = current_gear
	state.current_rpm = current_rpm
	state.clutch_value = clutch_value
	state.is_stalled = is_stalled


func update_clutch(delta, input: BikeInput):
	clutch_value = move_toward(clutch_value, input.clutch, clutch_speed * delta)


func get_clutch_engagement() -> float:
	"""Returns 0-1 engagement with friction zone curve (not linear)"""
	if clutch_value >= friction_zone_end:
		return 0.0  # Clutch fully disengaged (pulled in)
	if clutch_value <= friction_zone_start:
		return 1.0  # Clutch fully engaged (released)
	# Friction zone: smooth transition
	var zone_progress = (clutch_value - friction_zone_start) / (friction_zone_end - friction_zone_start)
	return 1.0 - zone_progress


func handle_gear_shifting(input: BikeInput):
	if input.gear_up_pressed:
		if clutch_value > gear_shift_threshold || dont_require_clutch:
			if current_gear < num_gears:
				current_gear += 1
				gear_changed.emit(current_gear)
		else:
			gear_grind.emit()
	elif input.gear_down_pressed:
		if clutch_value > gear_shift_threshold || dont_require_clutch:
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
	return state.max_speed * (lowest_ratio / gear_ratio)


func update_rpm(input: BikeInput):
	if is_stalled:
		current_rpm = 0.0
		# Restart engine with throttle + clutch while stalled
		if clutch_value > 0.5 and input.throttle > 0.3:
			is_stalled = false
			current_rpm = idle_rpm
			engine_started.emit()
		return

	# Calculate free-rev RPM (throttle controls directly when clutch in)
	var free_rev_rpm = lerpf(idle_rpm, max_rpm, input.throttle)

	# Calculate engaged RPM (locked to wheel speed)
	var gear_max_speed = get_max_speed_for_gear()
	var speed_ratio = state.speed / gear_max_speed if gear_max_speed > 0 else 0.0
	var engaged_rpm = lerpf(idle_rpm, max_rpm, clamp(speed_ratio, 0.0, 1.0))

	# Blend between free-rev and engaged based on friction zone engagement
	var engagement = get_clutch_engagement()
	var target_rpm = lerpf(free_rev_rpm, engaged_rpm, engagement)

	# Smooth RPM transitions (faster when free revving)
	var rpm_lerp_speed = lerpf(0.25, 0.1, engagement)
	current_rpm = lerpf(current_rpm, target_rpm, rpm_lerp_speed)

	# Check for stall (only when clutch is engaging and RPM drops too low)
	# Must check before clamping to idle_rpm
	if get_clutch_engagement() > 0.5 and current_rpm < stall_rpm and state.speed < 1.0:
		is_stalled = true
		current_gear = 1
		engine_stalled.emit()
		return

	# Clamp RPM
	current_rpm = clamp(current_rpm, idle_rpm, max_rpm)


func get_rpm_ratio() -> float:
	return (current_rpm - idle_rpm) / (max_rpm - idle_rpm)


func get_power_output(throttle: float) -> float:
	"""Returns power multiplier based on current RPM and gear"""
	if is_stalled:
		return 0.0

	var engagement = get_clutch_engagement()
	if engagement < 0.05:
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
	sync_to_state()
