class_name BikeTricks extends Node

signal skid_mark_requested(position: Vector3, rotation: Vector3)
signal tire_screech_start(volume: float)
signal tire_screech_stop
signal stoppie_stopped # Emitted when bike comes to rest during a stoppie

# Rotation tuning
@export var max_wheelie_angle: float = deg_to_rad(80)
@export var max_stoppie_angle: float = deg_to_rad(50)
@export var rotation_speed: float = 2.0
@export var return_speed: float = 3.0

# Wheelie RPM tuning - wheelies start at this RPM ratio and scale up to max at redline
@export var wheelie_rpm_threshold: float = 0.65 # RPM ratio where wheelies can start
@export var wheelie_rpm_full: float = 0.95 # RPM ratio for maximum wheelie effect

# Fishtail/drift tuning
@export var max_fishtail_angle: float = deg_to_rad(90)
@export var fishtail_speed: float = 8.0
@export var fishtail_recovery_speed: float = 3.0

@export var skid_volume: float = 0.5

# Shared state
var state: BikeState
var bike_physics:BikePhysics

# Skid marks
const SKID_SPAWN_INTERVAL: float = 0.025
var skid_spawn_timer: float = 0.0
var front_skid_spawn_timer: float = 0.0

# State
var pitch_angle: float = 0.0
var fishtail_angle: float = 0.0

# Input tracking for clutch dump detection
var last_throttle_input: float = 0.0
var last_clutch_input: float = 0.0


func setup(bike_state: BikeState, physics: BikePhysics):
    state = bike_state
    bike_physics = physics


func sync_to_state():
    state.pitch_angle = pitch_angle
    state.fishtail_angle = fishtail_angle


func handle_wheelie_stoppie(delta, input: BikeInput, rpm_ratio: float, clutch_value: float,
                            is_turning: bool, front_wheel_locked: bool = false, is_airborne: bool = false):
    # Airborne pitch control - free rotation with lean input
    if is_airborne:
        if abs(input.lean) > 0.1:
            var air_pitch_target = input.lean * max_wheelie_angle
            pitch_angle = move_toward(pitch_angle, air_pitch_target, rotation_speed * 1.5 * delta)
        return

    # Detect clutch dump
    var clutch_dump = last_clutch_input > 0.7 and clutch_value < 0.3 and input.throttle > 0.5
    last_throttle_input = input.throttle
    last_clutch_input = clutch_value

    # Can't START a wheelie/stoppie while turning, but can continue one
    var currently_in_wheelie = pitch_angle > deg_to_rad(5)
    var currently_in_stoppie = pitch_angle < deg_to_rad(-5)
    var can_start_trick = not is_turning

    # Wheelie logic - wheelies scale with RPM above threshold
    var wheelie_target = 0.0
    var rpm_above_threshold = rpm_ratio >= wheelie_rpm_threshold
    var can_pop_wheelie = input.lean > 0.3 and input.throttle > 0.7 and (rpm_above_threshold or clutch_dump)

    # Calculate how much wheelie power based on where we are in the RPM range
    # 0 at threshold, 1 at full RPM
    var rpm_wheelie_factor = 0.0
    if rpm_ratio >= wheelie_rpm_threshold:
        rpm_wheelie_factor = clamp((rpm_ratio - wheelie_rpm_threshold) / (wheelie_rpm_full - wheelie_rpm_threshold), 0.0, 1.0)

    if state.speed > 1 and (currently_in_wheelie or (can_pop_wheelie and can_start_trick)):
        if input.throttle > 0.3:
            # Wheelie intensity scales with both throttle AND rpm position in the power band
            wheelie_target = max_wheelie_angle * input.throttle * rpm_wheelie_factor
            wheelie_target += max_wheelie_angle * input.lean * 0.15

    # Stoppie logic - only works with progressive braking (not grabbed)
    # If front wheel is locked (brake grabbed), no stoppie - just skid
    var stoppie_target = 0.0
    if not front_wheel_locked:
        var wants_stoppie = input.lean < -0.1 and input.front_brake > 0.5
        if state.speed > 1 and (currently_in_stoppie or (wants_stoppie and can_start_trick)):
            stoppie_target = - max_stoppie_angle * input.front_brake * (1.0 - input.throttle * 0.5)
            stoppie_target += -max_stoppie_angle * (-input.lean) * 0.15

    # Apply pitch
    var was_in_stoppie = pitch_angle < deg_to_rad(-5)
    if wheelie_target > 0:
        pitch_angle = move_toward(pitch_angle, wheelie_target, rotation_speed * delta)
    elif stoppie_target < 0:
        pitch_angle = move_toward(pitch_angle, stoppie_target, rotation_speed * delta)
        if not was_in_stoppie:
            tire_screech_start.emit(skid_volume)
        # Check if bike stopped during stoppie - soft reset without position change
        if state.speed < 0.5 and currently_in_stoppie:
            pitch_angle = 0.0
            tire_screech_stop.emit()
            stoppie_stopped.emit()
    else:
        pitch_angle = move_toward(pitch_angle, 0, return_speed * delta)
        if was_in_stoppie and pitch_angle >= deg_to_rad(-5):
            tire_screech_stop.emit()


func handle_skidding(delta, input: BikeInput, rear_wheel_position: Vector3,
                      front_wheel_position: Vector3, bike_rotation: Vector3, is_on_floor: bool):
    var is_rear_skidding = input.rear_brake > 0.5 and state.speed > 2 and is_on_floor
    var is_front_skidding = state.is_front_wheel_locked() and state.speed > 2 and is_on_floor

    # Rear wheel skid
    if is_rear_skidding:
        skid_spawn_timer += delta
        if skid_spawn_timer >= SKID_SPAWN_INTERVAL:
            skid_spawn_timer = 0.0
            skid_mark_requested.emit(rear_wheel_position, bike_rotation)

        # Fishtail calculation - steering induces fishtail direction
        var steer_influence = state.steering_angle / bike_physics.max_steering_angle
        var target_fishtail = - steer_influence * max_fishtail_angle * input.rear_brake

        # Small natural wobble when skidding straight (random direction, small amplitude)
        if abs(steer_influence) < 0.1:
            var wobble_direction = 1.0 if fishtail_angle >= 0 else -1.0
            if abs(fishtail_angle) < deg_to_rad(2):
                wobble_direction = [-1.0, 1.0][randi() % 2]
            target_fishtail = wobble_direction * deg_to_rad(8) * input.rear_brake

        var speed_factor = clamp(state.speed / 20.0, 0.5, 1.5)
        target_fishtail *= speed_factor

        if abs(fishtail_angle) > deg_to_rad(15):
            target_fishtail *= 1.1 # Amplify once sliding

        fishtail_angle = move_toward(fishtail_angle, target_fishtail, fishtail_speed * delta)
    else:
        skid_spawn_timer = 0.0
        fishtail_angle = move_toward(fishtail_angle, 0, fishtail_recovery_speed * delta)

    # Front wheel skid (locked brake)
    if is_front_skidding:
        front_skid_spawn_timer += delta
        if front_skid_spawn_timer >= SKID_SPAWN_INTERVAL:
            front_skid_spawn_timer = 0.0
            skid_mark_requested.emit(front_wheel_position, bike_rotation)
        tire_screech_start.emit(skid_volume)
    else:
        front_skid_spawn_timer = 0.0

    # Tire screech for rear skid (only if not already screeching from front)
    if is_rear_skidding and not is_front_skidding:
        tire_screech_start.emit(skid_volume)


func get_fishtail_speed_loss(delta) -> float:
    """Returns how much speed to lose due to fishtail sliding"""
    if abs(fishtail_angle) > 0.01:
        var slide_friction = abs(fishtail_angle) / max_fishtail_angle
        return slide_friction * 15.0 * delta
    return 0.0


func is_in_wheelie() -> bool:
    return pitch_angle > deg_to_rad(5)


func is_in_stoppie() -> bool:
    return pitch_angle < deg_to_rad(-5)


func force_pitch(target: float, rate: float, delta):
    """Force pitch toward a target (used by crash system)"""
    pitch_angle = move_toward(pitch_angle, target, rate * delta)


func get_fishtail_vibration() -> Vector2:
    """Returns vibration intensity (weak, strong) for fishtail skidding"""
    var fishtail_intensity = abs(fishtail_angle) / max_fishtail_angle if max_fishtail_angle > 0 else 0.0
    if fishtail_intensity > 0.1:
        var weak = fishtail_intensity * 0.6
        var strong = fishtail_intensity * fishtail_intensity * 0.8
        return Vector2(weak, strong)
    return Vector2.ZERO


func reset():
    pitch_angle = 0.0
    fishtail_angle = 0.0
    skid_spawn_timer = 0.0
    front_skid_spawn_timer = 0.0
    last_throttle_input = 0.0
    last_clutch_input = 0.0
    sync_to_state()
