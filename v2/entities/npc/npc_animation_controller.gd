## Lite rider animation for NPCRiderEntity — seats the rider via its RiderVisual,
## then drives cosmetic lean / wheelie pitch on VisualRoot.
## No trick pipeline, no CustomAnimPlayer, no netfox. Runs locally on every
## peer — it derives purely from the synced transform + npc_state.
##
## NOTE: unlike the player scene, IKTargets is a CHILD of VisualRoot here, so
## the markers lean/pitch together with the bike — the rider stays glued on.
class_name NPCAnimationController extends Node

@export var npc: NPCRiderEntity
@export var max_lean_angle_deg: float = 30.0
## How much yaw rate (rad/s) maps to lean angle.
@export var lean_per_yaw_rate: float = 0.5
@export var wheelie_pitch_deg: float = 35.0
@export var crash_roll_deg: float = 80.0
@export var rotation_blend_speed: float = 6.0
## Past this distance from the active camera the rider's rig stops updating — limb IK is
## cosmetic, so a distant rider holding its last pose reads fine. The bike keeps driving,
## colliding and syncing; only the skeleton work stops, which is why this is safe during
## races where culling the simulation would not be. Same idea as the VisibleOnScreenEnabler3D
## approach in the Godot 3D perf docs, by distance so it doesn't pop as the camera swings.
@export var rig_cull_distance: float = 60.0
## How often the distance check runs. It's cheap, but there's no reason to do it per tick.
@export var rig_cull_check_interval: float = 0.5

var _initialized: bool = false
var _prev_yaw: float = 0.0
var _yaw_rate: float = 0.0

## Rig LOD state — see rig_cull_distance.
var _ik_ctrl: IKController
var _rig_active: bool = true
var _rig_next_check_ms: int = 0


## Called from NPCRiderEntity._ready after skins are applied. Same sequence as
## PlayerEntity._init_ik().
func initialize() -> void:
	_ik_ctrl = npc.character_skin.ik_controller
	npc.visual_root.seat()
	_prev_yaw = npc.rotation.y
	_initialized = true


func _physics_process(delta: float):
	if !_initialized:
		return
	var t := Time.get_ticks_usec()  # PROF: temp
	_update_rig_lod()
	# Lean/pitch stays on at any distance — it's two lerps on one node, and a bike that
	# stops leaning through corners is obvious in a way a frozen wrist isn't.
	if _rig_active:
		npc.visual_root.sync_targets()
	_update_yaw_rate(delta)
	_apply_visual_root_rotation(delta)
	DebugUtils.Prof("npc.anim", t)  # PROF: temp


## Toggle the cosmetic rider rig by distance from the active camera. Runs on every peer
## against its own view — the rig is local cosmetics, nothing here is synced or authoritative.
##
## Note this cuts Process time as much as Physics: Skeleton3D runs its modifiers (the
## FABRIK3D solve) on the idle callback by default, so switching the modifier off lands in
## a different budget than the target writes below.
func _update_rig_lod() -> void:
	var now := Time.get_ticks_msec()
	if now < _rig_next_check_ms:
		return
	_rig_next_check_ms = now + int(rig_cull_check_interval * 1000.0)

	var cam := get_viewport().get_camera_3d()
	# No camera yet while a level is still loading — leave the rig as it is until there is one.
	if cam == null:
		return
	var active := (
		npc.global_position.distance_squared_to(cam.global_position)
		< rig_cull_distance * rig_cull_distance
	)
	if active == _rig_active:
		return
	_rig_active = active
	# enable_ik/disable_ik already own the modifier + hip-placement flags.
	if active:
		_ik_ctrl.enable_ik()
	else:
		_ik_ctrl.disable_ik()
	_ik_ctrl.set_physics_process(active)


func _update_yaw_rate(delta: float) -> void:
	var yaw := npc.rotation.y
	var raw_rate := wrapf(yaw - _prev_yaw, -PI, PI) / delta
	_prev_yaw = yaw
	# Smooth — on clients yaw arrives stepwise at network rate.
	_yaw_rate = lerpf(_yaw_rate, raw_rate, 10.0 * delta)


## visual_root.rotation.z = lean, .x = wheelie pitch (negative x pitches the
## front up — same mapping as AnimationController._apply_pitch_ground).
func _apply_visual_root_rotation(delta: float) -> void:
	var target_roll: float = 0.0
	var target_pitch: float = 0.0
	match npc.npc_state:
		NPCRiderEntity.NPCState.CRASHED:
			target_roll = deg_to_rad(crash_roll_deg)
		NPCRiderEntity.NPCState.WHEELIE:
			target_pitch = -deg_to_rad(wheelie_pitch_deg)
			target_roll = _lean_target()
		_:
			target_roll = _lean_target()

	var vr := npc.visual_root
	var blend := rotation_blend_speed * delta
	vr.rotation.z = lerp_angle(vr.rotation.z, target_roll, blend)
	vr.rotation.x = lerp_angle(vr.rotation.x, target_pitch, blend)


func _lean_target() -> float:
	var max_lean := deg_to_rad(max_lean_angle_deg)
	# Turning left (+yaw rate) leans left (-z roll).
	return clampf(-_yaw_rate * lean_per_yaw_rate, -max_lean, max_lean)


func _get_configuration_warnings() -> PackedStringArray:
	var issues := PackedStringArray()
	if npc == null:
		issues.append("npc must not be empty")
	return issues
