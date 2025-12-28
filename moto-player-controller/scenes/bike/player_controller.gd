class_name PlayerController extends CharacterBody3D

# Node references
@onready var mesh: Node3D = %Mesh
@onready var rear_wheel: Marker3D = %RearWheelMarker
@onready var front_wheel: Marker3D = %FrontWheelMarker
@onready var engine_sound: AudioStreamPlayer = %EngineSound
@onready var tire_screech: AudioStreamPlayer = %TireScreechSound

@onready var gear_label: Label = %GearLabel
@onready var speed_label: Label = %SpeedLabel
@onready var throttle_bar: ProgressBar = %ThrottleBar
@onready var brake_danger_bar: ProgressBar = %BrakeDangerBar

# Components
@onready var bike_gearing: BikeGearing = %BikeGearing
@onready var bike_steering: BikeSteering = %BikeSteering
@onready var bike_tricks: BikeTricks = %BikeTricks
@onready var bike_physics: BikePhysics = %BikePhysics
@onready var bike_crash: BikeCrash = %BikeCrash
@onready var bike_audio: BikeAudio = %BikeAudio
@onready var bike_ui: BikeUI = %BikeUI

# Skid marks
@export var skidmark_texture = preload("res://assets/skidmarktex.png")
const SKID_MARK_LIFETIME: float = 5.0

# Spawn tracking
var spawn_position: Vector3
var spawn_rotation: Vector3

func _ready():
    spawn_position = global_position
    spawn_rotation = rotation

    # Setup bike_audio and UI components with node references
    bike_audio.setup(engine_sound, tire_screech)
    bike_ui.setup(gear_label, speed_label, throttle_bar, brake_danger_bar)

    # Connect component signals
    bike_gearing.gear_grind.connect(_on_gear_grind)
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

    # Input gathering
    var throttle = Input.get_action_strength("throttle_pct")
    var front_brake = Input.get_action_strength("brake_front_pct")
    var rear_brake = Input.get_action_strength("brake_rear")
    var steer_input = bike_steering.get_steer_input()

    # Gearing
    bike_gearing.handle_gear_shifting()
    bike_gearing.update_rpm(throttle)

    # Physics / acceleration
    bike_physics.handle_acceleration(
        delta, throttle, front_brake, rear_brake,
        bike_gearing.get_power_output(throttle),
        bike_gearing.get_max_speed_for_gear(),
        bike_gearing.clutch_value,
        bike_gearing.is_stalled,
        bike_crash.is_front_wheel_locked()
    )

    # Steering
    bike_steering.handle_steering(delta, bike_physics.idle_tip_angle)
    bike_steering.update_lean(delta, steer_input, bike_tricks.pitch_angle, bike_physics.idle_tip_angle)

    # Tricks (wheelies, stoppies, skidding)
    bike_tricks.handle_wheelie_stoppie(
        delta,
        bike_gearing.get_rpm_ratio(),
        bike_gearing.clutch_value,
        bike_steering.is_turning(),
        bike_crash.is_front_wheel_locked()
    )
    bike_tricks.handle_skidding(delta, rear_wheel.global_position, global_rotation, is_on_floor())

    # Idle tipping
    bike_physics.handle_idle_tipping(delta, throttle, steer_input, bike_steering.lean_angle)

    # Check for controlled brake stop
    bike_physics.check_brake_stop(bike_steering.steering_angle, bike_steering.lean_angle)

    # Crash detection
    bike_crash.check_crash_conditions(
        delta,
        bike_tricks.pitch_angle,
        bike_steering.lean_angle,
        bike_physics.idle_tip_angle,
        bike_steering.steering_angle,
        front_brake
    )

    # Force stoppie if brake danger while going straight
    if bike_crash.should_force_stoppie():
        bike_tricks.force_pitch(-bike_crash.crash_stoppie_threshold * 1.2, 4.0, delta)

    # Movement
    _apply_movement(delta)
    _apply_mesh_rotation()

    # Audio and UI
    bike_audio.update_engine_audio(throttle)
    bike_ui.update_ui()

    move_and_slide()


func _apply_movement(delta):
    var forward = - global_transform.basis.z

    if bike_physics.speed > 0.5:
        var turn_rate = bike_steering.get_turn_rate()
        rotate_y(-bike_steering.steering_angle * turn_rate * delta)

        # Fishtail rotation and speed loss
        if abs(bike_tricks.fishtail_angle) > 0.01:
            rotate_y(bike_tricks.fishtail_angle * delta * 4.0)
            bike_physics.apply_fishtail_friction(delta, bike_tricks.get_fishtail_speed_loss(delta))

    velocity = forward * bike_physics.speed
    velocity = bike_physics.apply_gravity(delta, velocity, is_on_floor())


func _apply_mesh_rotation():
    mesh.transform = Transform3D.IDENTITY

    # Pitch pivot selection
    var pivot: Vector3
    if bike_tricks.pitch_angle >= 0:
        pivot = rear_wheel.position
    else:
        pivot = front_wheel.position

    # Apply pitch
    if bike_tricks.pitch_angle != 0:
        _rotate_mesh_around_pivot(pivot, Vector3.RIGHT, bike_tricks.pitch_angle)

    # Apply lean (including idle tip)
    var total_lean = bike_steering.lean_angle + bike_physics.idle_tip_angle
    if total_lean != 0:
        mesh.rotate_z(total_lean)


func _rotate_mesh_around_pivot(pivot: Vector3, axis: Vector3, angle: float):
    var t = mesh.transform
    t.origin -= pivot
    t = t.rotated(axis, angle)
    t.origin += pivot
    mesh.transform = t


func _handle_crash_state(delta):
    if bike_crash.handle_crash_state(delta):
        _respawn()
        return

    # Animate bike_crash
    if bike_crash.crash_pitch_direction != 0:
        bike_tricks.force_pitch(bike_crash.crash_pitch_direction * deg_to_rad(90), 3.0, delta)
    elif bike_crash.crash_lean_direction != 0:
        bike_steering.lean_angle = move_toward(bike_steering.lean_angle, bike_crash.crash_lean_direction * deg_to_rad(90), 3.0 * delta)

        # Slide with friction during lowside
        if bike_physics.speed > 0.1:
            var forward = - global_transform.basis.z
            velocity = forward * bike_physics.speed
            bike_physics.speed = move_toward(bike_physics.speed, 0, 20.0 * delta)
            move_and_slide()

    _apply_mesh_rotation()


func _respawn():
    global_position = spawn_position
    rotation = spawn_rotation
    velocity = Vector3.ZERO
    mesh.transform = Transform3D.IDENTITY

    # Reset all components
    bike_gearing.reset()
    bike_steering.reset()
    bike_tricks.reset()
    bike_physics.reset()
    bike_crash.reset()
    bike_ui.stop_vibration()


# Signal handlers
func _on_gear_grind():
    bike_audio.play_gear_grind()


func _on_engine_stalled():
    bike_audio.stop_engine()


func _on_skid_mark_requested(pos: Vector3, rot: Vector3):
    _spawn_skid_mark(pos, rot)


func _on_tire_screech_start(volume: float):
    bike_audio.play_tire_screech(volume)


func _on_tire_screech_stop():
    bike_audio.stop_tire_screech()


func _on_stoppie_stopped():
    # Soft reset: like stalling but keep engine running
    bike_steering.reset()
    bike_physics.speed = 0.0
    bike_physics.idle_tip_angle = 0.0
    velocity = Vector3.ZERO


func _on_brake_stopped():
    # Soft reset: bike stopped via braking while upright
    bike_steering.reset()
    velocity = Vector3.ZERO


func _on_crashed(pitch_dir: float, lean_dir: float):
    # Keep speed for lowside crashes
    if lean_dir != 0 and pitch_dir == 0:
        bike_physics.speed *= 0.7
    else:
        bike_physics.speed = 0.0
        velocity = Vector3.ZERO

    # Play tire screech for lowside
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
