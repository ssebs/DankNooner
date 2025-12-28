class_name PlayerController extends CharacterBody3D

# Node references
@onready var mesh = %Mesh
@onready var rear_wheel = %RearWheelMarker
@onready var front_wheel = %FrontWheelMarker
@onready var engine_sound = %EngineSound
@onready var tire_screech = %TireScreechSound

@onready var gear_label = %GearLabel
@onready var speed_label = %SpeedLabel
@onready var throttle_bar = %ThrottleBar
@onready var brake_danger_bar = %BrakeDangerBar

# Components
@onready var gearing: BikeGearing = $BikeGearing
@onready var steering: BikeSteering = $BikeSteering
@onready var tricks: BikeTricks = $BikeTricks
@onready var physics: BikePhysics = $BikePhysics
@onready var crash: BikeCrash = $BikeCrash
@onready var audio: BikeAudio = $BikeAudio
@onready var ui: BikeUI = $BikeUI

# Skid marks
var skidmark_texture = preload("res://assets/skidmarktex.png")
const SKID_MARK_LIFETIME: float = 5.0

# Spawn tracking
var spawn_position: Vector3
var spawn_rotation: Vector3


func _ready():
	spawn_position = global_position
	spawn_rotation = rotation

	# Setup audio and UI components with node references
	audio.setup(engine_sound, tire_screech)
	ui.setup(gear_label, speed_label, throttle_bar, brake_danger_bar)

	# Connect component signals
	gearing.gear_grind.connect(_on_gear_grind)
	gearing.engine_stalled.connect(_on_engine_stalled)
	tricks.skid_mark_requested.connect(_on_skid_mark_requested)
	tricks.tire_screech_start.connect(_on_tire_screech_start)
	tricks.tire_screech_stop.connect(_on_tire_screech_stop)
	crash.crashed.connect(_on_crashed)

	# Share max_speed with components that need it
	gearing.max_speed = physics.max_speed
	steering.max_speed = physics.max_speed
	crash.max_speed = physics.max_speed


func _physics_process(delta):
	# Sync component state
	_sync_component_state()

	if crash.is_crashed:
		_handle_crash_state(delta)
		return

	# Input gathering
	var throttle = Input.get_action_strength("throttle_pct")
	var front_brake = Input.get_action_strength("brake_front_pct")
	var rear_brake = Input.get_action_strength("brake_rear")
	var steer_input = steering.get_steer_input()

	# Gearing
	gearing.handle_gear_shifting()
	gearing.update_rpm(throttle)

	# Physics / acceleration
	physics.handle_acceleration(
		delta, throttle, front_brake, rear_brake,
		gearing.get_power_output(throttle),
		gearing.get_max_speed_for_gear(),
		gearing.clutch_value,
		gearing.is_stalled
	)

	# Steering
	steering.handle_steering(delta)
	steering.update_lean(delta, steer_input, tricks.pitch_angle, physics.idle_tip_angle)

	# Tricks (wheelies, stoppies, skidding)
	tricks.handle_wheelie_stoppie(
		delta,
		gearing.get_rpm_ratio(),
		gearing.clutch_value,
		steering.is_turning()
	)
	tricks.handle_skidding(delta, rear_wheel.global_position, global_rotation, is_on_floor())

	# Idle tipping
	physics.handle_idle_tipping(delta, throttle, steering.lean_angle, steering.max_lean_angle)

	# Crash detection
	crash.check_crash_conditions(
		delta,
		tricks.pitch_angle,
		steering.lean_angle,
		physics.idle_tip_angle,
		steering.steering_angle,
		front_brake
	)

	# Force stoppie if brake danger while going straight
	if crash.should_force_stoppie():
		tricks.force_pitch(-crash.crash_stoppie_threshold * 1.2, 4.0, delta)

	# Movement
	_apply_movement(delta)
	_apply_mesh_rotation()

	# Audio and UI
	audio.update_engine_audio(throttle)
	ui.update_ui()

	move_and_slide()


func _sync_component_state():
	"""Keep component external state in sync"""
	# Gearing needs speed
	gearing.speed = physics.speed

	# Steering needs speed
	steering.speed = physics.speed

	# Tricks needs speed and steering
	tricks.speed = physics.speed
	tricks.steering_angle = steering.steering_angle
	tricks.max_steering_angle = steering.max_steering_angle

	# Crash needs speed and steering
	crash.speed = physics.speed
	crash.max_steering_angle = steering.max_steering_angle

	# Audio needs engine state
	audio.speed = physics.speed
	audio.current_rpm = gearing.current_rpm
	audio.idle_rpm = gearing.idle_rpm
	audio.max_rpm = gearing.max_rpm
	audio.is_stalled = gearing.is_stalled

	# UI needs display state
	ui.current_gear = gearing.current_gear
	ui.speed = physics.speed
	ui.current_rpm = gearing.current_rpm
	ui.idle_rpm = gearing.idle_rpm
	ui.max_rpm = gearing.max_rpm
	ui.is_stalled = gearing.is_stalled
	ui.brake_danger_level = crash.brake_danger_level
	ui.fishtail_angle = tricks.fishtail_angle
	ui.max_fishtail_angle = tricks.max_fishtail_angle


func _apply_movement(delta):
	var forward = -global_transform.basis.z

	if physics.speed > 0.5:
		var turn_rate = steering.get_turn_rate()
		rotate_y(-steering.steering_angle * turn_rate * delta)

		# Fishtail rotation and speed loss
		if abs(tricks.fishtail_angle) > 0.01:
			rotate_y(tricks.fishtail_angle * delta * 4.0)
			physics.apply_fishtail_friction(delta, tricks.get_fishtail_speed_loss(delta))

	velocity = forward * physics.speed
	velocity = physics.apply_gravity(delta, velocity, is_on_floor())


func _apply_mesh_rotation():
	mesh.transform = Transform3D.IDENTITY

	# Pitch pivot selection
	var pivot: Vector3
	if tricks.pitch_angle >= 0:
		pivot = rear_wheel.position
	else:
		pivot = front_wheel.position

	# Apply pitch
	if tricks.pitch_angle != 0:
		_rotate_mesh_around_pivot(pivot, Vector3.RIGHT, tricks.pitch_angle)

	# Apply lean (including idle tip)
	var total_lean = steering.lean_angle + physics.idle_tip_angle
	if total_lean != 0:
		mesh.rotate_z(total_lean)


func _rotate_mesh_around_pivot(pivot: Vector3, axis: Vector3, angle: float):
	var t = mesh.transform
	t.origin -= pivot
	t = t.rotated(axis, angle)
	t.origin += pivot
	mesh.transform = t


func _handle_crash_state(delta):
	if crash.handle_crash_state(delta):
		_respawn()
		return

	# Animate crash
	if crash.crash_pitch_direction != 0:
		tricks.force_pitch(crash.crash_pitch_direction * deg_to_rad(90), 3.0, delta)
	elif crash.crash_lean_direction != 0:
		steering.lean_angle = move_toward(steering.lean_angle, crash.crash_lean_direction * deg_to_rad(90), 3.0 * delta)

		# Slide with friction during lowside
		if physics.speed > 0.1:
			var forward = -global_transform.basis.z
			velocity = forward * physics.speed
			physics.speed = move_toward(physics.speed, 0, 20.0 * delta)
			move_and_slide()

	_apply_mesh_rotation()


func _respawn():
	global_position = spawn_position
	rotation = spawn_rotation
	velocity = Vector3.ZERO
	mesh.transform = Transform3D.IDENTITY

	# Reset all components
	gearing.reset()
	steering.reset()
	tricks.reset()
	physics.reset()
	crash.reset()
	ui.stop_vibration()


# Signal handlers
func _on_gear_grind():
	audio.play_gear_grind()


func _on_engine_stalled():
	audio.stop_engine()


func _on_skid_mark_requested(pos: Vector3, rot: Vector3):
	_spawn_skid_mark(pos, rot)


func _on_tire_screech_start(volume: float):
	audio.play_tire_screech(volume)


func _on_tire_screech_stop():
	audio.stop_tire_screech()


func _on_crashed(pitch_dir: float, lean_dir: float):
	# Keep speed for lowside crashes
	if lean_dir != 0 and pitch_dir == 0:
		physics.speed *= 0.7
	else:
		physics.speed = 0.0
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
