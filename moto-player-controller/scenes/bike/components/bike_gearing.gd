class_name BikeGearing extends Node

signal gear_changed(new_gear: int)
signal engine_stalled
signal engine_started
signal gear_grind # Tried to shift without clutch

# Gear system
@export var num_gears: int = 6
@export var max_rpm: float = 9000.0
@export var idle_rpm: float = 1000.0
@export var stall_rpm: float = 800.0
@export var gear_ratios: Array[float] = [2.92, 2.05, 1.6, 1.46, 1.15, 1.0]

# Clutch tuning
@export var clutch_engage_speed: float = 6.0 # How fast clutch pulls in when held
@export var clutch_release_speed: float = 2.5 # How fast clutch releases when not held
@export var clutch_tap_amount: float = 0.35 # How much a tap adds to clutch value
@export var clutch_hold_delay: float = 0.05 # Seconds before hold starts engaging fully
@export var gear_shift_threshold: float = 0.2 # Clutch value needed to shift
@export var rpm_blend_speed: float = 4.0 # How fast RPM changes when clutch engaged

# Shared state
var state: BikeState
var bike_physics: BikePhysics

# Input state (from signals)
var throttle: float = 0.0
var clutch_held: bool = false
var clutch_just_pressed: bool = false

# Local state
var clutch_hold_time: float = 0.0


func setup(bike_state: BikeState, physics: BikePhysics, input: BikeInput):
    state = bike_state
    bike_physics = physics
    input.throttle_changed.connect(func(v): throttle = v)
    input.clutch_held_changed.connect(_on_clutch_input)
    input.gear_up_pressed.connect(_on_gear_up)
    input.gear_down_pressed.connect(_on_gear_down)


func _on_clutch_input(held: bool, just_pressed: bool):
    clutch_held = held
    clutch_just_pressed = just_pressed


func _on_gear_up():
    if state.clutch_value > gear_shift_threshold || state.is_easy_mode:
        if state.current_gear < num_gears:
            state.current_gear += 1
            gear_changed.emit(state.current_gear)
    else:
        gear_grind.emit()


func _on_gear_down():
    if state.clutch_value > gear_shift_threshold || state.is_easy_mode:
        if state.current_gear > 1:
            state.current_gear -= 1
            gear_changed.emit(state.current_gear)
    else:
        gear_grind.emit()


func update_clutch(delta: float):
    if clutch_held:
        clutch_hold_time += delta
        if clutch_just_pressed:
            # Tap: instantly add to clutch value
            state.clutch_value = minf(state.clutch_value + clutch_tap_amount, 1.0)
        elif clutch_hold_time >= clutch_hold_delay:
            # Held past delay: pull in fully
            state.clutch_value = move_toward(state.clutch_value, 1.0, clutch_engage_speed * delta)
    else:
        clutch_hold_time = 0.0
        # Release: slowly let clutch out
        state.clutch_value = move_toward(state.clutch_value, 0.0, clutch_release_speed * delta)


func get_clutch_engagement() -> float:
    """Returns 0-1 where 0 = clutch pulled in (disengaged), 1 = clutch released (engaged to wheel)"""
    return 1.0 - state.clutch_value


func get_max_speed_for_gear() -> float:
    var gear_ratio = gear_ratios[state.current_gear - 1]
    var lowest_ratio = gear_ratios[num_gears - 1]
    return bike_physics.max_speed * (lowest_ratio / gear_ratio)


func update_rpm(delta: float):
    if state.is_stalled:
        state.current_rpm = 0.0
        # Restart engine with throttle + clutch while stalled
        if state.clutch_value > 0.5 and throttle > 0.3:
            state.is_stalled = false
            state.current_rpm = idle_rpm
            engine_started.emit()
        return

    var engagement = get_clutch_engagement()

    # Calculate wheel-driven RPM based on wheel speed
    var gear_max_speed = get_max_speed_for_gear()
    var speed_ratio = state.speed / gear_max_speed if gear_max_speed > 0 else 0.0
    var wheel_rpm = speed_ratio * max_rpm

    # Throttle-driven RPM (instant - no smoothing, engine revs freely)
    var throttle_rpm = lerpf(idle_rpm, max_rpm, throttle)

    # Blend between throttle RPM and wheel RPM based on clutch engagement
    # engagement = 0: clutch in, engine free-revs (fast response)
    # engagement = 1: clutch out, engine locked to wheel (follows wheel speed)
    var target_rpm = lerpf(throttle_rpm, wheel_rpm, engagement)

    # RPM blend speed: fast when free-revving, slower when engaged to wheel
    var blend_speed = lerpf(12.0, rpm_blend_speed, engagement)
    state.current_rpm = lerpf(state.current_rpm, target_rpm, blend_speed * delta)

    # Check for stall when clutch is mostly engaged and RPM too low
    if engagement > 0.9 and state.current_rpm < stall_rpm:
        state.is_stalled = true
        state.current_gear = 1
        engine_stalled.emit()
        return

    state.current_rpm = clamp(state.current_rpm, idle_rpm, max_rpm)

func get_rpm_ratio() -> float:
    if max_rpm <= idle_rpm:
        return 0.0
    return (state.current_rpm - idle_rpm) / (max_rpm - idle_rpm)


func get_power_output() -> float:
    """Returns power multiplier based on current RPM and gear"""
    if state.is_stalled:
        return 0.0

    var engagement = get_clutch_engagement()
    if engagement < 0.05:
        return 0.0

    var rpm_ratio = get_rpm_ratio()
    var power_curve = rpm_ratio * (2.0 - rpm_ratio) # Peaks around 75% RPM

    var gear_ratio = gear_ratios[state.current_gear - 1]
    var base_ratio = gear_ratios[num_gears - 1]
    var torque_multiplier = gear_ratio / base_ratio

    return throttle * power_curve * torque_multiplier * engagement


func is_clutch_dump(last_clutch: float) -> bool:
    """Returns true if clutch was just dumped while revving"""
    return last_clutch > 0.7 and state.clutch_value < 0.3 and throttle > 0.5


func reset():
    state.current_gear = 1
    state.current_rpm = idle_rpm
    state.is_stalled = false
    state.clutch_value = 0.0
    clutch_hold_time = 0.0
