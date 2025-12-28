class_name PlayerController extends CharacterBody3D

@onready var mesh = %Mesh
@onready var rear_wheel = %RearWheelMarker
@onready var front_wheel = %FrontWheelMarker
@onready var audio_player = %AudioStreamPlayer

# Rotation angles
var pitch_angle: float = 0.0
var lean_angle: float = 0.0

# Movement
var speed: float = 0.0
var steering_angle: float = 0.0

# Rotation tuning
@export var max_wheelie_angle: float = deg_to_rad(80)
@export var max_stoppie_angle: float = deg_to_rad(50)
@export var max_lean_angle: float = deg_to_rad(40)
@export var rotation_speed: float = 2.0
@export var return_speed: float = 3.0
@export var min_turn_radius: float = 0.25   # Tight turns at low speed
@export var max_turn_radius: float = 3.0   # Wide turns at high speed

# Movement tuning
@export var max_speed: float = 50.0
@export var acceleration: float = 15.0
@export var brake_strength: float = 25.0
@export var friction: float = 5.0
@export var steering_speed: float = 5.5
@export var max_steering_angle: float = deg_to_rad(35)
@export var turn_speed: float = 2.0  # How fast the bike actually turns

# Crash tuning
@export var crash_wheelie_threshold: float = deg_to_rad(75)  # Wheelie too far
@export var crash_stoppie_threshold: float = deg_to_rad(45)  # Stoppie too far
@export var crash_brake_rate_threshold: float = 10.0  # Brake input change per second
@export var idle_tip_speed_threshold: float = 3.0  # Speed below which you start tipping
@export var idle_tip_rate: float = 0.5  # How fast you tip when idle
@export var crash_lean_threshold: float = deg_to_rad(80)  # Fall over at this lean
@export var respawn_delay: float = 2.0

# Gravity
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Crash state
var is_crashed: bool = false
var crash_timer: float = 0.0
var crash_pitch_direction: float = 0.0  # Non-zero for wheelie/stoppie crashes
var crash_lean_direction: float = 0.0   # Non-zero for sideways crashes
var last_brake_input: float = 0.0
var idle_tip_angle: float = 0.0
var spawn_position: Vector3
var spawn_rotation: Vector3

func _ready():
    spawn_position = global_position
    spawn_rotation = rotation

func _physics_process(delta):
    if is_crashed:
        handle_crash_state(delta)
        return

    handle_acceleration(delta)
    handle_steering(delta)
    handle_lean_input(delta)
    handle_idle_tipping(delta)
    check_crash_conditions(delta)
    apply_movement(delta)
    apply_mesh_rotation()
    update_audio()
    move_and_slide()


func handle_acceleration(delta):
    var throttle = Input.get_action_strength("throttle_pct")
    var front_brake = Input.get_action_strength("brake_front_pct")
    var rear_brake = Input.get_action_strength("brake_rear")
    
    # Accelerate
    if throttle > 0:
        speed = move_toward(speed, max_speed * throttle, acceleration * delta)
    
    # Brake
    var total_brake = clamp(front_brake + rear_brake, 0, 1)
    if total_brake > 0:
        speed = move_toward(speed, 0, brake_strength * total_brake * delta)
    
    # Natural friction when no input
    if throttle == 0 and total_brake == 0:
        speed = move_toward(speed, 0, friction * delta)


func handle_steering(delta):
    var steer_input = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")

    # Snappier steering at low speeds
    var speed_factor = 1.0 + (1.0 - clamp(speed / 10.0, 0.0, 1.0)) * 1.5  # Up to 2.5x faster at low speed
    var effective_steering_speed = steering_speed * speed_factor

    if steer_input != 0:
        steering_angle = move_toward(steering_angle, max_steering_angle * steer_input, effective_steering_speed * delta)
    else:
        steering_angle = move_toward(steering_angle, 0, effective_steering_speed * 2 * delta)


func handle_lean_input(delta):
    var lean_input = Input.get_action_strength("lean_back") - Input.get_action_strength("lean_forward")
    var steer_input = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
    var front_brake = Input.get_action_strength("brake_front_pct")
    var rear_brake = Input.get_action_strength("brake_rear")
    var is_braking = (front_brake + rear_brake) > 0

    # Pitch (wheelie/stoppie)
    if lean_input > 0 and speed > 1:
        # Wheelie - only when moving
        pitch_angle = move_toward(pitch_angle, max_wheelie_angle * lean_input, rotation_speed * delta)
    elif lean_input < 0 and is_braking and speed > 1:
        # Stoppie - only when braking and moving
        pitch_angle = move_toward(pitch_angle, -max_stoppie_angle * abs(lean_input), rotation_speed * delta)
    else:
        pitch_angle = move_toward(pitch_angle, 0, return_speed * delta)
    
    # Side lean (mix of input and speed-based auto-lean in turns)
    var turn_lean = 0.0
    if speed > 1:
        turn_lean = -steering_angle * 0.6  # Auto-lean into turns

    # More lean at low speeds (under 5)
    var low_speed_lean_mult = 1.0 + (1.0 - clamp(speed / 5.0, 0.0, 1.0)) * 0.8  # Up to 1.8x lean at very low speed

    var target_lean = (-max_lean_angle * steer_input * 0.4 + turn_lean) * low_speed_lean_mult
    lean_angle = move_toward(lean_angle, target_lean, rotation_speed * delta)

func apply_movement(delta):
    var forward = -global_transform.basis.z
    
    if speed > 0.5:
        # Lerp between tight and wide turns based on speed
        var speed_pct = speed / max_speed
        var turn_radius = lerp(min_turn_radius, max_turn_radius, speed_pct)
        var turn_rate = turn_speed / turn_radius
        rotate_y(-steering_angle * turn_rate * delta)
    
    velocity = forward * speed
    
    if not is_on_floor():
        velocity.y -= gravity * delta


func apply_mesh_rotation():
    mesh.transform = Transform3D.IDENTITY
    
    # Pitch pivot
    var pivot: Vector3
    if pitch_angle >= 0:
        pivot = rear_wheel.position
    else:
        pivot = front_wheel.position
    
    # Apply pitch
    if pitch_angle != 0:
        rotate_mesh_around_pivot(pivot, Vector3.RIGHT, pitch_angle)
    
    # Apply lean (including idle tip)
    var total_lean = lean_angle + idle_tip_angle
    if total_lean != 0:
        mesh.rotate_z(total_lean)


func rotate_mesh_around_pivot(pivot: Vector3, axis: Vector3, angle: float):
    var t = mesh.transform
    t.origin -= pivot
    t = t.rotated(axis, angle)
    t.origin += pivot
    mesh.transform = t


func update_audio():
    var throttle = Input.get_action_strength("throttle_pct")

    # RPM Audio Pitch
    if throttle > 0:
        if not audio_player.playing:
            audio_player.play()
        audio_player.pitch_scale = clampf(throttle, 0.5, 3.0)
    elif speed > 0.5:
        # Engine winds down gradually when coasting
        if not audio_player.playing:
            audio_player.play()
        audio_player.pitch_scale = move_toward(audio_player.pitch_scale, 0.5, 0.02)
    else:
        if audio_player.playing:
            audio_player.stop()


func handle_idle_tipping(delta):
    var throttle = Input.get_action_strength("throttle_pct")

    if speed < idle_tip_speed_threshold and throttle == 0:
        # Start tipping over when idle with no throttle
        if idle_tip_angle == 0:
            # Pick a random direction to tip
            idle_tip_angle = 0.01 if randf() > 0.5 else -0.01
        idle_tip_angle = move_toward(idle_tip_angle, sign(idle_tip_angle) * crash_lean_threshold, idle_tip_rate * delta)
    else:
        # Throttle or speed prevents/reverts tipping
        idle_tip_angle = move_toward(idle_tip_angle, 0, idle_tip_rate * 2.0 * delta)


func check_crash_conditions(delta):
    var front_brake = Input.get_action_strength("brake_front_pct")
    var rear_brake = Input.get_action_strength("brake_rear")
    var total_brake = clamp(front_brake + rear_brake, 0, 1)

    # Check brake input rate (too sudden = crash)
    var brake_rate = abs(total_brake - last_brake_input) / delta
    last_brake_input = total_brake

    var crash_reason = ""

    # debugs
    print("brake_rate")
    print(brake_rate)

    # Wheelie too far
    if pitch_angle > crash_wheelie_threshold:
        crash_reason = "wheelie"
        crash_pitch_direction = 1  # Fall backward
        crash_lean_direction = 0

    # Stoppie too far
    elif pitch_angle < -crash_stoppie_threshold:
        crash_reason = "stoppie"
        crash_pitch_direction = -1  # Fall forward
        crash_lean_direction = 0

    # Brake too hard too fast
    elif brake_rate > crash_brake_rate_threshold and speed > 5:
        crash_reason = "brake"
        crash_pitch_direction = 0
        crash_lean_direction = 1 if randf() > 0.5 else -1

    # Idle tipping over
    elif abs(idle_tip_angle) >= crash_lean_threshold:
        crash_reason = "idle_tip"
        crash_pitch_direction = 0
        crash_lean_direction = sign(idle_tip_angle)

    # Total lean too far (from steering + idle tip)
    elif abs(lean_angle + idle_tip_angle) >= crash_lean_threshold:
        crash_reason = "lean"
        crash_pitch_direction = 0
        crash_lean_direction = sign(lean_angle + idle_tip_angle)

    if crash_reason != "":
        trigger_crash()


func trigger_crash():
    is_crashed = true
    crash_timer = 0.0
    speed = 0.0
    velocity = Vector3.ZERO


func handle_crash_state(delta):
    crash_timer += delta

    # Animate the crash - fall sideways or forward/back
    if crash_pitch_direction != 0:
        # Wheelie/stoppie crash - continue rotating in pitch direction
        pitch_angle = move_toward(pitch_angle, crash_pitch_direction * deg_to_rad(90), 3.0 * delta)
    elif crash_lean_direction != 0:
        # Sideways crash - fall over to the side
        lean_angle = move_toward(lean_angle, crash_lean_direction * deg_to_rad(90), 3.0 * delta)

    apply_mesh_rotation()

    if crash_timer >= respawn_delay:
        respawn()


func respawn():
    is_crashed = false
    global_position = spawn_position
    rotation = spawn_rotation
    pitch_angle = 0.0
    lean_angle = 0.0
    idle_tip_angle = 0.0
    steering_angle = 0.0
    speed = 0.0
    velocity = Vector3.ZERO
    last_brake_input = 0.0
    crash_pitch_direction = 0.0
    crash_lean_direction = 0.0
    mesh.transform = Transform3D.IDENTITY
