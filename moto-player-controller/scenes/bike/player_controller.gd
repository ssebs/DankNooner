class_name PlayerController extends CharacterBody3D

# Node references
@onready var mesh: Node3D = %Mesh
@onready var rear_wheel: Marker3D = %RearWheelMarker
@onready var front_wheel: Marker3D = %FrontWheelMarker
@onready var engine_sound: AudioStreamPlayer = %EngineSound
@onready var tire_screech: AudioStreamPlayer = %TireScreechSound
@onready var engine_grind: AudioStreamPlayer = %EngineGrindSound
@onready var exhaust_pops: AudioStreamPlayer = %ExhaustPopsSound

@onready var gear_label: Label = %GearLabel
@onready var speed_label: Label = %SpeedLabel
@onready var throttle_bar: ProgressBar = %ThrottleBar
@onready var brake_danger_bar: ProgressBar = %BrakeDangerBar
@onready var clutch_bar: ProgressBar = %ClutchBar
@onready var difficulty_label: Label = %DifficultyLabel

# Components
@onready var bike_input: BikeInput = %BikeInput
@onready var bike_gearing: BikeGearing = %BikeGearing
@onready var bike_tricks: BikeTricks = %BikeTricks
@onready var bike_physics: BikePhysics = %BikePhysics
@onready var bike_crash: BikeCrash = %BikeCrash
@onready var bike_audio: BikeAudio = %BikeAudio
@onready var bike_ui: BikeUI = %BikeUI

# Shared state
var state: BikeState = BikeState.new()

# Skid marks
@export var skidmark_texture = preload("res://assets/skidmarktex.png")
const SKID_MARK_LIFETIME: float = 5.0

# Ground alignment
@export var ground_align_speed: float = 10.0
var ground_pitch: float = 0.0

# Spawn tracking
var spawn_position: Vector3
var spawn_rotation: Vector3


func _ready():
    spawn_position = global_position
    spawn_rotation = rotation

    # Setup all components with shared state
    bike_physics.setup(state)
    bike_gearing.setup(state, bike_physics)
    bike_tricks.setup(state, bike_physics)
    bike_crash.setup(state, bike_physics)
    bike_audio.setup(state, engine_sound, tire_screech, engine_grind, exhaust_pops)
    bike_ui.setup(state, bike_input, bike_crash, bike_tricks, gear_label, speed_label, throttle_bar, brake_danger_bar, clutch_bar, difficulty_label)

    # Connect component signals
    bike_gearing.gear_grind.connect(_on_gear_grind)
    bike_gearing.gear_changed.connect(_on_gear_changed)
    bike_gearing.engine_stalled.connect(_on_engine_stalled)
    bike_tricks.skid_mark_requested.connect(_on_skid_mark_requested)
    bike_tricks.tire_screech_start.connect(_on_tire_screech_start)
    bike_tricks.tire_screech_stop.connect(_on_tire_screech_stop)
    bike_tricks.stoppie_stopped.connect(_on_stoppie_stopped)
    bike_physics.brake_stopped.connect(_on_brake_stopped)
    bike_crash.crashed.connect(_on_crashed)


func _physics_process(delta):
    if bike_crash.is_crashed:
        _handle_crash_state(delta)
        return

    # Gearing
    bike_gearing.update_clutch(delta, bike_input)
    bike_gearing.handle_gear_shifting(bike_input)
    bike_gearing.update_rpm(delta, bike_input)
    bike_gearing.sync_to_state()

    # Physics / acceleration
    bike_physics.handle_acceleration(
        delta, bike_input,
        bike_gearing.get_power_output(bike_input.throttle),
        bike_gearing.get_max_speed_for_gear(),
        bike_gearing.clutch_value,
        bike_gearing.is_stalled,
        bike_crash.is_front_wheel_locked()
    )

    # Steering and lean
    bike_physics.handle_steering(delta, bike_input)
    bike_physics.update_lean(delta, bike_input)
    bike_physics.handle_fall_physics(delta, bike_input)

    # Tricks (wheelies, stoppies, skidding)
    bike_tricks.handle_wheelie_stoppie(
        delta, bike_input,
        bike_gearing.get_rpm_ratio(),
        bike_gearing.clutch_value,
        bike_physics.is_turning(),
        bike_crash.is_front_wheel_locked(),
        not is_on_floor()
    )
    bike_tricks.handle_skidding(
        delta, bike_input,
        rear_wheel.global_position,
        front_wheel.global_position,
        global_rotation,
        is_on_floor()
    )
    bike_tricks.sync_to_state()

    # Check for controlled brake stop
    bike_physics.check_brake_stop(bike_input)

    # Crash detection
    if is_on_floor():
        bike_crash.check_crash_conditions(
            delta, bike_input,
            bike_tricks.pitch_angle,
            state.lean_angle,
            state.fall_angle,
            state.steering_angle
        )
    else:
        bike_crash.check_airborne_crash(
            state.lean_angle,
            state.fall_angle,
            bike_tricks.pitch_angle
        )
    bike_crash.sync_to_state()

    # Force stoppie if brake danger while going straight
    if bike_crash.should_force_stoppie(bike_input):
        bike_tricks.force_pitch(-bike_crash.crash_stoppie_threshold * 1.2, 4.0, delta)

    # Movement
    _apply_movement(delta)
    _apply_mesh_rotation()

    # Audio and UI
    bike_audio.update_engine_audio(delta, bike_input, bike_gearing.get_rpm_ratio())
    bike_ui.update_ui(bike_input, bike_gearing.get_rpm_ratio())

    move_and_slide()

    # Align to ground
    _align_to_ground(delta)

    # Check for collisions
    _check_collision_crash()


func _check_collision_crash():
    if bike_crash.is_crashed:
        return

    for i in get_slide_collision_count():
        var collision = get_slide_collision(i)
        var collider = collision.get_collider()

        # Check if collider is on layer 2 (bit 1)
        var is_crash_layer = false
        if collider is CollisionObject3D:
            is_crash_layer = collider.get_collision_layer_value(2)
        elif collider is CSGShape3D and collider.use_collision:
            is_crash_layer = (collider.collision_layer & 2) != 0

        if is_crash_layer:
            var normal = collision.get_normal()
            if state.speed > 5:
                var local_normal = global_transform.basis.inverse() * normal
                bike_crash.trigger_collision_crash(local_normal)
                return


func _align_to_ground(delta):
    if is_on_floor():
        var floor_normal = get_floor_normal()
        var forward_dir = - global_transform.basis.z
        var forward_dot = forward_dir.dot(floor_normal)
        var target_pitch = asin(clamp(forward_dot, -1.0, 1.0))
        ground_pitch = lerp(ground_pitch, target_pitch, ground_align_speed * delta)
    else:
        ground_pitch = lerp(ground_pitch, 0.0, ground_align_speed * 0.5 * delta)


func _apply_movement(delta):
    var forward = - global_transform.basis.z

    if state.speed > 0.5:
        var turn_rate = bike_physics.get_turn_rate()
        rotate_y(-state.steering_angle * turn_rate * delta)

        if abs(bike_tricks.fishtail_angle) > 0.01:
            rotate_y(bike_tricks.fishtail_angle * delta * 1.5)
            bike_physics.apply_fishtail_friction(delta, bike_tricks.get_fishtail_speed_loss(delta))

    var vertical_velocity = velocity.y
    velocity = forward * state.speed
    velocity.y = vertical_velocity
    velocity = bike_physics.apply_gravity(delta, velocity, is_on_floor())


func _apply_mesh_rotation():
    mesh.transform = Transform3D.IDENTITY

    if ground_pitch != 0:
        mesh.rotate_x(-ground_pitch)

    var pivot: Vector3
    if bike_tricks.pitch_angle >= 0:
        pivot = rear_wheel.position
    else:
        pivot = front_wheel.position

    if bike_tricks.pitch_angle != 0:
        _rotate_mesh_around_pivot(pivot, Vector3.RIGHT, bike_tricks.pitch_angle)

    var total_lean = state.lean_angle + state.fall_angle
    if total_lean != 0:
        mesh.rotate_z(total_lean)


func _rotate_mesh_around_pivot(pivot: Vector3, axis: Vector3, angle: float):
    var t = mesh.transform
    t.origin -= pivot
    t = t.rotated(axis, angle)
    t.origin += pivot
    mesh.transform = t


func _handle_crash_state(delta):
    if bike_crash.handle_crash_state(delta, state.speed):
        _respawn()
        return

    if bike_crash.crash_pitch_direction != 0:
        bike_tricks.force_pitch(bike_crash.crash_pitch_direction * deg_to_rad(90), 3.0, delta)
    elif bike_crash.crash_lean_direction != 0:
        state.fall_angle = move_toward(state.fall_angle, bike_crash.crash_lean_direction * deg_to_rad(90), 3.0 * delta)

        if state.speed > 0.1:
            var forward = - global_transform.basis.z
            velocity = forward * state.speed
            state.speed = move_toward(state.speed, 0, 20.0 * delta)
            move_and_slide()

    _apply_mesh_rotation()


func _respawn():
    global_position = spawn_position
    rotation = spawn_rotation
    velocity = Vector3.ZERO
    mesh.transform = Transform3D.IDENTITY

    # Reset all components (removed duplicate bike_physics.reset())
    bike_gearing.reset()
    bike_physics.reset()
    bike_tricks.reset()
    bike_crash.reset()
    bike_input.reset()


# Signal handlers
func _on_gear_grind():
    bike_audio.play_gear_grind()


func _on_gear_changed(_new_gear: int):
    bike_audio.on_gear_changed()


func _on_engine_stalled():
    bike_audio.stop_engine()


func _on_skid_mark_requested(pos: Vector3, rot: Vector3):
    _spawn_skid_mark(pos, rot)


func _on_tire_screech_start(volume: float):
    bike_audio.play_tire_screech(volume)


func _on_tire_screech_stop():
    bike_audio.stop_tire_screech()


func _on_stoppie_stopped():
    bike_physics.reset()
    state.speed = 0.0
    state.fall_angle = 0.0
    velocity = Vector3.ZERO


func _on_brake_stopped():
    bike_physics.reset()
    velocity = Vector3.ZERO


func _on_crashed(pitch_dir: float, lean_dir: float):
    if lean_dir != 0 and pitch_dir == 0:
        state.speed *= 0.7
    else:
        state.speed = 0.0
        velocity = Vector3.ZERO

    if lean_dir != 0:
        tire_screech.volume_db = 0.0
        tire_screech.play()


func _spawn_skid_mark(pos: Vector3, rot: Vector3):
    var decal = Decal.new()
    decal.texture_albedo = skidmark_texture
    decal.size = Vector3(0.15, 0.5, 0.4)
    decal.cull_mask = 1

    get_tree().current_scene.add_child(decal)

    decal.global_position = Vector3(pos.x, pos.y - 0.05, pos.z)
    decal.global_rotation = rot

    var timer = get_tree().create_timer(SKID_MARK_LIFETIME)
    timer.timeout.connect(func(): if is_instance_valid(decal): decal.queue_free())
