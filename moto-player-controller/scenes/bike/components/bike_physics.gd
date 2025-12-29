class_name BikePhysics extends Node

signal brake_stopped


# Movement tuning
@export var max_speed: float = 60.0
@export var acceleration: float = 15.0
@export var brake_strength: float = 25.0
@export var friction: float = 8.0

# Steering tuning
@export var steering_speed: float = 4.0
@export var max_steering_angle: float = deg_to_rad(35)
@export var max_lean_angle: float = deg_to_rad(45)
@export var lean_speed: float = 3.5

# Turn radius
@export var min_turn_radius: float = 0.25
@export var max_turn_radius: float = 3.0
@export var turn_speed: float = 2.0

# Fall physics
@export var fall_rate: float = 0.5 # How fast bike falls over at zero speed
@export var stability_speed: float = 10.0 # Speed where bike becomes stable
@export var high_speed_instability_start: float = 45.0 # Speed where instability begins again
@export var crash_lean_threshold: float = deg_to_rad(80)
@export var countersteer_factor: float = 1.2 # How much lean induces automatic steering

# Shared state
var state: BikeState

# Local state
var speed: float = 0.0
var fall_angle: float = 0.0 # How far bike has fallen over
var has_started_moving: bool = false
var steering_angle: float = 0.0
var lean_angle: float = 0.0

# Gravity
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func setup(bike_state: BikeState):
    state = bike_state
    state.crash_lean_threshold = crash_lean_threshold


func sync_to_state():
    state.speed = speed
    state.steering_angle = steering_angle
    state.lean_angle = lean_angle
    state.fall_angle = fall_angle


func handle_acceleration(delta, input: BikeInput, power_output: float, gear_max_speed: float,
                          clutch_engaged: float, is_stalled: bool, front_wheel_locked: bool = false):
    # Braking
    if input.front_brake > 0 or input.rear_brake > 0:
        var front_effectiveness = 0.6 if front_wheel_locked else 1.0
        var rear_effectiveness = 0.6 if input.rear_brake > 0.5 else 1.0
        var total_braking = clamp(input.front_brake * front_effectiveness + input.rear_brake * rear_effectiveness, 0, 1)
        speed = move_toward(speed, 0, brake_strength * total_braking * delta)

    if is_stalled:
        speed = move_toward(speed, 0, friction * delta)
        return

    # Acceleration
    if power_output > 0:
        if speed < gear_max_speed:
            speed += acceleration * power_output * delta
            speed = min(speed, gear_max_speed)
        else:
            speed = move_toward(speed, gear_max_speed, friction * 2.0 * delta)

    # Friction when coasting
    if input.throttle == 0 and input.front_brake == 0 and input.rear_brake == 0:
        var drag = friction * (1.5 - clutch_engaged * 0.5)
        speed = move_toward(speed, 0, drag * delta)


func handle_fall_physics(delta, _input: BikeInput):
    """
    Fall physics with speed-based stability curve:
    - Below stability_speed: bike falls over (low speed wobble)
    - Between stability_speed and high_speed_instability_start: stable zone
    - Above high_speed_instability_start: high speed wobble begins
    """
    if speed > 0.25:
        has_started_moving = true

    if !has_started_moving:
        fall_angle = 0.0
        return

    # Calculate stability based on speed
    # Low speed: unstable (0 to 1 as speed increases to stability_speed)
    var low_speed_stability = clamp(speed / stability_speed, 0.0, 1.0)

    # High speed: unstable again (1 to 0 as speed goes from high_speed_instability_start to max_speed)
    var high_speed_instability = 0.0
    if speed > high_speed_instability_start:
        high_speed_instability = clamp((speed - high_speed_instability_start) / (max_speed - high_speed_instability_start), 0.0, 1.0)

    # Combined stability: stable in the middle, unstable at both extremes
    var stability = low_speed_stability * (1.0 - high_speed_instability)

    # Target: upright (0) when stable, keep falling when not
    if stability > 0.9:
        # Stable zone - pull upright
        fall_angle = move_toward(fall_angle, 0, fall_rate * 2.0 * delta)
    else:
        # Unstable - fall in current direction
        var fall_direction = sign(fall_angle) if abs(fall_angle) > 0.01 else sign(lean_angle + 0.001)
        var fall_strength = (1.0 - stability) * fall_rate
        fall_angle += fall_direction * fall_strength * delta


func apply_fishtail_friction(_delta, fishtail_speed_loss: float):
    speed = move_toward(speed, 0, fishtail_speed_loss)


func check_brake_stop(input: BikeInput):
    var is_upright = abs(lean_angle + fall_angle) < deg_to_rad(15)
    var is_straight = abs(steering_angle) < deg_to_rad(10)

    var total_brake = clamp(input.front_brake + input.rear_brake, 0.0, 1.0)
    if speed < 0.5 and total_brake > 0.3 and is_upright and is_straight and has_started_moving:
        speed = 0.0
        fall_angle = 0.0
        has_started_moving = false
        brake_stopped.emit()


func apply_gravity(delta, velocity: Vector3, is_on_floor: bool) -> Vector3:
    if !is_on_floor:
        velocity.y -= gravity * delta
    return velocity


func handle_steering(delta, input: BikeInput):
    """
    Countersteering: lean angle induces automatic steering in that direction.
    When you lean right, the bike naturally steers right (turns into the lean).
    Steering radius depends on lean angle and speed.
    Releasing steer while on throttle straightens the bike.
    """
    # If no steer input and throttle is applied, straighten out
    if abs(input.steer) < 0.1 and input.throttle > 0.1:
        steering_angle = lerpf(steering_angle, 0, steering_speed * delta)
        return

    # Total lean (visual lean + fall) drives automatic countersteer
    var total_lean = lean_angle + fall_angle

    # Countersteer: lean induces steering in same direction
    # More lean = tighter turn radius (more steering)
    var lean_induced_steer = - total_lean * countersteer_factor

    # Player input adds to the automatic countersteer
    var input_steer = max_steering_angle * input.steer

    # At higher speeds, countersteer effect is stronger (bike turns more from lean)
    var speed_factor = clamp(speed / 20.0, 0.3, 1.0)
    var target_steer = clamp(input_steer + lean_induced_steer * speed_factor, -max_steering_angle, max_steering_angle)

    # Smooth interpolation to target
    steering_angle = lerpf(steering_angle, target_steer, steering_speed * delta)


func update_lean(delta, input: BikeInput):
    """
    Visual lean angle based on steering and player input.
    Fall angle is added separately in mesh rotation.
    """
    # Lean from steering (centripetal force in turns)
    var speed_factor = clamp(speed / 20.0, 0.0, 1.0)
    var steer_lean = - steering_angle * speed_factor * 1.2

    # Direct player lean input
    var input_lean = - input.steer * max_lean_angle * 0.3

    var target_lean = steer_lean + input_lean
    target_lean = clamp(target_lean, -max_lean_angle, max_lean_angle)

    # Smooth interpolation
    lean_angle = lerpf(lean_angle, target_lean, lean_speed * delta)


func get_turn_rate() -> float:
    var speed_pct = speed / max_speed
    var turn_radius = lerpf(min_turn_radius, max_turn_radius, speed_pct)
    return turn_speed / turn_radius


func is_turning() -> bool:
    return abs(steering_angle) > 0.2


func reset():
    speed = 0.0
    fall_angle = 0.0
    has_started_moving = false
    steering_angle = 0.0
    lean_angle = 0.0
    sync_to_state()
