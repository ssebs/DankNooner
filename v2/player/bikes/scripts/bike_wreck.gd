## Visual-only stand-in for the bike while crashed: a rigid body that IKTargets (bike mesh, lights,
## exhaust) rides, launched per CrashType. Simulated locally on every peer, so tumbles differ per screen.
class_name BikeWreck extends RigidBody3D

@export var player_entity: PlayerEntity
@export var ik_targets: Node3D

## Roll speed (rad/s) tipping a lowside / wall crash down onto the side it leaned toward.
const TIP_SPEED: float = 3.0
## Upward pop (m/s) a highside throws the bike with.
const HIGHSIDE_POP: float = 4.0
## Barrel-roll speed (rad/s) over the high side.
const HIGHSIDE_ROLL_SPEED: float = 8.0
## End-over-end speed (rad/s) added to a highside.
const HIGHSIDE_FLIP_SPEED: float = 3.0
## Min contact speed (m/s) that throws sparks and grinds.
const GRIND_MIN_SPEED: float = 2.0
## A riderless bike only rests on a side: while touching with |up · world up| above ON_SIDE_MAX_UP_DOT
## (upright or upside down), it's rolled toward horizontal at SIDE_ROLL_ACCEL (rad/s²), at any speed.
const ON_SIDE_MAX_UP_DOT: float = 0.5
const SIDE_ROLL_ACCEL: float = 30.0
## Speed change (m/s) within one physics step that counts as a hard hit, and min gap (s) between hit sounds.
const IMPACT_MIN_SPEED_CHANGE: float = 4.0
const IMPACT_COOLDOWN: float = 0.15

@onready var wreck_shape: CollisionShape3D = %WreckShape
@onready var wreck_sparks: GPUParticles3D = %WreckSparks
## Positional grind for every rider; hit only for remote ones. See PlayerEntity.play_rider_sound().
@onready var wreck_grind: AudioStreamPlayer3D = %WreckGrind
@onready var wreck_impact: AudioStreamPlayer3D = %WreckImpact

var _ik_targets_rest: Transform3D
var _ik_targets_offset: Transform3D
var _contact_pos: Vector3
var _is_grinding: bool = false
var _grind_playing: bool = false
var _prev_velocity: Vector3
var _impact_pending: bool = false
var _impact_cooldown: float = 0.0


func _ready() -> void:
	add_collision_exception_with(player_entity)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var touching := state.get_contact_count() > 0
	var bike_up := state.transform.basis.y
	var up_dot := bike_up.dot(Vector3.UP)

	# Upright it's rolling on its tires, so only a side or upside-down slide scrapes.
	_is_grinding = (
		touching
		and up_dot <= ON_SIDE_MAX_UP_DOT
		and state.linear_velocity.length() > GRIND_MIN_SPEED
	)
	if _is_grinding:
		_contact_pos = state.get_contact_collider_position(0)

	if touching and (state.linear_velocity - _prev_velocity).length() > IMPACT_MIN_SPEED_CHANGE:
		_impact_pending = true
	_prev_velocity = state.linear_velocity

	if touching and absf(up_dot) > ON_SIDE_MAX_UP_DOT:
		# Upright: tip bike_up away from world up. Upside down: toward it. Either way, toward a side.
		var roll_axis := Vector3.UP.cross(bike_up).normalized() * signf(up_dot)
		# Dead vertical has no lean to follow, so roll about the bike's length.
		if roll_axis.is_zero_approx():
			roll_axis = state.transform.basis.z
		state.angular_velocity += roll_axis * SIDE_ROLL_ACCEL * state.step


func _process(delta: float) -> void:
	if freeze:
		return
	ik_targets.global_transform = global_transform * _ik_targets_offset
	wreck_sparks.global_position = _contact_pos
	wreck_sparks.emitting = _is_grinding
	_set_grind(_is_grinding)

	_impact_cooldown -= delta
	if _impact_pending and _impact_cooldown <= 0.0:
		_impact_cooldown = IMPACT_COOLDOWN
		var clunk := player_entity.audio_manager.get_sound_event(AudioManager.Sfx.CLUNK_GEAR_CHANGE)
		player_entity.play_rider_sound(clunk, wreck_impact)
	_impact_pending = false


func start(crash_type: CrashController.CrashType, launch_velocity: Vector3) -> void:
	_ik_targets_rest = ik_targets.transform
	global_transform = ik_targets.global_transform.orthonormalized()
	_ik_targets_offset = global_transform.affine_inverse() * ik_targets.global_transform
	_fit_shape()

	var fwd := Vector3(launch_velocity.x, 0.0, launch_velocity.z).normalized()
	# Tips the bike's up further from vertical, i.e. down onto the side it leans toward.
	var tip_axis := Vector3.UP.cross(global_basis.y).normalized()
	# Dead upright (e.g. a steep-slope stall) has no lean to follow, so fall along the bike's length.
	if tip_axis.is_zero_approx():
		tip_axis = global_basis.z

	# Unfreeze first: going static -> dynamic zeroes any velocity set while frozen.
	freeze = false
	linear_velocity = launch_velocity
	_prev_velocity = launch_velocity
	angular_velocity = tip_axis * TIP_SPEED
	if crash_type == CrashController.CrashType.HIGHSIDE:
		linear_velocity += Vector3.UP * HIGHSIDE_POP
		angular_velocity = (
			-tip_axis * HIGHSIDE_ROLL_SPEED + Vector3.UP.cross(fwd) * HIGHSIDE_FLIP_SPEED
		)


func stop() -> void:
	freeze = true
	_is_grinding = false
	wreck_sparks.emitting = false
	_set_grind(false)
	ik_targets.transform = _ik_targets_rest


## Box around the bike's meshes in body space, so every skin and mod tumbles on its own silhouette.
func _fit_shape() -> void:
	var to_body := global_transform.affine_inverse()
	var box := AABB()
	var mesh_node := player_entity.bike_skin.mesh_node
	for mesh: MeshInstance3D in mesh_node.find_children("*", "MeshInstance3D", true, false):
		var mesh_box := (to_body * mesh.global_transform) * mesh.get_aabb()
		box = mesh_box if box.size.is_zero_approx() else box.merge(mesh_box)
	var shape := BoxShape3D.new()
	shape.size = box.size
	wreck_shape.shape = shape
	wreck_shape.position = box.get_center()


## Start/stop the looping grind on slide edges, like SkidmarkController's tire squeal.
func _set_grind(on: bool) -> void:
	if on == _grind_playing:
		return
	_grind_playing = on
	# Positional for the local rider too, so the grind follows the bike as it slides away.
	if on:
		player_entity.audio_manager.get_sound_event(AudioManager.Sfx.CRASH_GRIND).play_on(wreck_grind)
	else:
		wreck_grind.stop()


## A despawn mid-crash never hits stop(), so cut the loop here.
func _exit_tree() -> void:
	_set_grind(false)
