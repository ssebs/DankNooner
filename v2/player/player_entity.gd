@tool
## make sure to set HACK region's vars!
## audio_manager & username
class_name PlayerEntity extends CharacterBody3D

## Used for internals
signal respawned(peer_id: int)

## Used for GameMode
signal crashed(peer_id: int)
# signal trick_started(peer_id: int, trick_type: int)
# signal trick_ended(peer_id: int, trick_type: int)

@export var bike_definition: BikeSkinDefinition:
	set(value):
		bike_definition = value
		if Engine.is_editor_hint() and is_node_ready():
			_editor_refresh_from_bike_definition()
@export var character_definition: CharacterSkinDefinition:
	set(value):
		character_definition = value
		if (
			Engine.is_editor_hint()
			and is_node_ready()
			and character_skin
			and character_skin.skin_definition != value
		):
			character_skin.skin_definition = value
@export var collision_shape_3d: CollisionShape3D

@export var input_controller: InputController
@export var animation_controller: AnimationController
@export var gearing_controller: GearingController
@export var trick_controller: TrickController
@export var crash_controller: CrashController
@export var movement_controller: MovementController
@export var camera_controller: CameraController
@export var boost_controller: BoostController

## Local-client only: log per-tick reconciliation correction to speed/velocity + rollback
## depth (rubber-band probe). Off by default; toggle in the inspector to diagnose desync.
@export var debug_netcode_metrics: bool = false

@export_group("IK Targets")
@export var butt_target: Marker3D
@export var left_hand_target: Marker3D
@export var right_hand_target: Marker3D
@export var left_foot_target: Marker3D
@export var right_foot_target: Marker3D
@export var chest_target: Marker3D
@export var head_target: Marker3D
@export var left_arm_magnet: Marker3D
@export var right_arm_magnet: Marker3D
@export var left_leg_magnet: Marker3D
@export var right_leg_magnet: Marker3D

## Editor-only authoring handles for bike wheel positions. Drag in the viewport, then click
## "Save Default Pose" on AnimationController to write into BikeSkinDefinition. Runtime reads
## those .tres values directly (raycasts, wheelie/stoppie pivot) — these nodes are not used.
@export_group("Bike Wheel Markers (editor authoring)")
@export var front_wheel_ground_marker: Marker3D
@export var rear_wheel_ground_marker: Marker3D
@export var front_wheel_front_marker: Marker3D
@export var rear_wheel_back_marker: Marker3D

@onready var controllers_node: Node3D = %_Controllers

@onready var visual_root: Node3D = %VisualRoot
@onready var character_skin: CharacterSkin = %CharacterSkin
@onready var bike_skin: BikeSkin = %BikeSkin
@onready var name_label: Label3D = %NameLabel
@onready var rear_raycast: RayCast3D = %RearRayCast
@onready var front_raycast: RayCast3D = %FrontRayCast
@onready var rollback_sync: RollbackSynchronizer = %RollbackSynchronizer

var is_local_client: bool = false

#region HACK - set from spawn_manager
var audio_manager: AudioManager
var settings_manager: SettingsManager
var gamemode_manager: GamemodeManager
var hud_manager: HUDManager
var username: String:
	set(v):
		username = v
		if is_node_ready():
			name_label.text = username
# `name` is also set from spawn_manager
#endregion

#region Netfox sync'd
# `global_transform`, `velocity` also sync'd
#endregion

#region DELETE_ME

# Crash state (synced)
var is_crashed: bool = false

# Brake danger (local, display only)
var grip_usage: float = 0.0
#endregion

# Discrete actions (rb_* pattern)
var rb_do_respawn: bool = false
## Set by SpawnManager.crash_player when another racer rammed us — we can't see
## that collision ourselves (slide collisions only report what WE moved into).
var rb_do_crash: bool = false
## Set by SpawnManager.grant_boost on a pickup — adds one boost segment. boost_amount is synced
## state, so this rides the rollback tick + resim re-application (like rb_do_respawn) to survive.
var rb_add_boost: bool = false
## Set by SpawnManager.max_boost_player (debug console) — fills the meter. Rides the same
## rollback tick + resim machinery as rb_add_boost.
var rb_do_max_boost: bool = false
## Persistent respawn point. Set by SpawnManager.respawn_player_at (e.g. TeleportTask),
## reset to identity to fall back to `get_parent().global_transform` (player_spawn_pos).
## Persists across respawns so crashes after a checkpoint return to the checkpoint.
var rb_respawn_transform: Transform3D = Transform3D()
## One-shot respawn override, consumed by the next do_respawn() WITHOUT touching the
## persistent respawn point. Free roam crash respawns set this so you respawn where you
## crashed, while the pause-menu respawn button still returns to rb_respawn_transform.
var rb_respawn_transform_oneshot: Transform3D = Transform3D()

## Tick the last respawn was anchored to + its resolved target. Netfox resimulates
## recent ticks when late input arrives (server: remote players; client: own prediction),
## rebuilding state from pre-respawn history — without re-applying the respawn on the
## resim of that tick, the teleport gets silently undone. Worse, the server's first
## application lands on a predicted tick, which netfox never broadcasts, so clients
## would never see race-grid teleports at all. See _rollback_tick.
var _respawn_tick: int = -1
var _respawn_target: Transform3D = Transform3D()

## Same resim protection for the boost grant: remember the tick + resulting meter so a resim of
## that tick re-applies the same absolute value instead of dropping the +1.
var _boost_grant_tick: int = -1
var _boost_grant_amount: float = 0.0

# Process-side state tracking (not sync'd)
var _prev_is_crashed: bool = false

# Netcode metrics probe (debug_netcode_metrics) — predicted state snapshot taken before
# netfox re-applies authoritative state each rollback loop, on the local client only.
var _dbg_pre_speed: float = 0.0
var _dbg_pre_vel_len: float = 0.0
var _dbg_log_file: FileAccess = null


func _ready():
	floor_max_angle = deg_to_rad(170.0) # allow riding on steep ramps, loops, ceilings
	_init_mesh()
	_init_collision_shape()
	_init_ik()
	_init_raycasts()
	_init_controller_handlers()
	animation_controller.initialize()

	if Engine.is_editor_hint():
		return

	add_to_group(UtilsConstants.GROUPS["Racers"])

	# await get_tree().process_frame

	# Network authority
	set_multiplayer_authority(1)
	input_controller.set_multiplayer_authority(int(name))
	rollback_sync.process_settings()

	call_deferred("_deferred_init")


func _rollback_tick(delta: float, tick: int, _is_fresh: bool):
	if Engine.is_editor_hint():
		return

	if rb_do_respawn:
		rb_do_respawn = false
		_respawn_tick = tick
		_respawn_target = _pick_respawn_target()
		do_respawn()
	elif tick == _respawn_tick:
		# Resimulation of the respawn tick — re-apply the synced-state part (skip
		# one-time cosmetics like mesh/IK/audio) so the resim doesn't undo the teleport.
		_apply_respawn_state()

	if rb_do_crash:
		rb_do_crash = false
		on_crash()

	# Boost grant: apply once, then re-apply the same meter on any resim of that tick (boost
	# is drained below, so this must land before the controllers run).
	if rb_add_boost:
		rb_add_boost = false
		boost_controller.add_segment()
		_boost_grant_tick = tick
		_boost_grant_amount = boost_controller.boost_amount
	elif rb_do_max_boost:
		rb_do_max_boost = false
		boost_controller.fill()
		_boost_grant_tick = tick
		_boost_grant_amount = boost_controller.boost_amount
	elif tick == _boost_grant_tick:
		boost_controller.boost_amount = _boost_grant_amount

	# Run other controllers (ORDER MATTERS)
	# Boost first — ahead of every controller AND evaluated even while crashed (unlike the
	# rest, which bail on is_crashed), so a crash mid-boost cancels the burn and its camera
	# FX instead of latching them until the respawn.
	boost_controller.on_movement_rollback_tick(delta)
	movement_controller.on_movement_rollback_tick(delta)
	gearing_controller.on_movement_rollback_tick(delta)
	trick_controller.on_movement_rollback_tick(delta)
	crash_controller.on_movement_rollback_tick(delta)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# Detect crash state transition outside rollback (safe for signals/RPCs)
	if is_crashed and !_prev_is_crashed:
		crashed.emit(int(name))
		if is_local_client and audio_manager:
			audio_manager.stop_revs()
			# TODO - use meme mode instead of hard coding this randomization
			randomize()
			var r = randi_range(0, 2)
			match r:
				0:
					audio_manager.play_bowling_crash()
				1:
					audio_manager.play_vine_boom()
				2:
					audio_manager.play_nuke()
	_prev_is_crashed = is_crashed

	if !is_local_client:
		return


#region init
## Editor-only: keep bike-derived state in sync when bike_definition is swapped in the
## inspector. Without this, mesh/steering update via BikeSkin's setter but wheel markers,
## collision, raycasts and IK pose stay pointed at the old .tres.
func _editor_refresh_from_bike_definition() -> void:
	if bike_definition == null:
		return
	if bike_skin and bike_skin.skin_definition != bike_definition:
		bike_skin.skin_definition = bike_definition
	if collision_shape_3d:
		_init_collision_shape()
	if front_raycast and rear_raycast:
		_init_raycasts()
	# AnimationController._editor_auto_init() handles wheel markers, IK pose, hand/foot sync.
	if animation_controller:
		animation_controller._editor_auto_init()


## set definitions and apply mesh/colors/markers
func _init_mesh():
	bike_skin.skin_definition = bike_definition
	bike_skin._apply_definition()
	character_skin.skin_definition = character_definition
	character_skin.apply_definition()


## set collision shape from bike_definition
func _init_collision_shape():
	collision_shape_3d.shape = bike_definition.collision_shape

	collision_shape_3d.position = bike_definition.collision_position_offset
	collision_shape_3d.rotation_degrees = bike_definition.collision_rotation_offset_degrees
	collision_shape_3d.scale = bike_definition.collision_scale_multiplier


## Position ground raycasts at wheel positions from bike_definition.
## Wheel markers are authored under VisualRoot (yawed 180° to face -Z), so their
## positions are VisualRoot-local. The raycasts live in PlayerEntity space, so
## rotate the offsets by VisualRoot's basis or they land on the mirrored side.
func _init_raycasts():
	var b := visual_root.transform.basis
	front_raycast.position = b * bike_definition.front_wheel_ground_position + Vector3.UP * 0.5
	front_raycast.target_position = Vector3.DOWN * 1.5
	rear_raycast.position = b * bike_definition.rear_wheel_ground_position + Vector3.UP * 0.5
	rear_raycast.target_position = Vector3.DOWN * 1.5


func _init_ik():
	var ik_ctrl = character_skin.ik_controller
	butt_target.position = bike_definition.seat_marker_position
	ik_ctrl.set_targets(
		butt_target,
		left_hand_target,
		right_hand_target,
		left_foot_target,
		right_foot_target,
		chest_target,
		head_target,
		left_arm_magnet,
		right_arm_magnet,
		left_leg_magnet,
		right_leg_magnet
	)
	_apply_rider_pose_from_definition()
	ik_ctrl._create_ik()
	character_skin.enable_ik()


func _apply_rider_pose_from_definition():
	var bd = bike_definition
	if bd.chest_position is Vector3 and bd.chest_position != Vector3.ZERO:
		chest_target.position = bd.chest_position
	if bd.chest_rotation is Vector3 and bd.chest_rotation != Vector3.ZERO:
		chest_target.rotation = bd.chest_rotation
	if bd.head_position is Vector3 and bd.head_position != Vector3.ZERO:
		head_target.position = bd.head_position
	if bd.head_rotation is Vector3 and bd.head_rotation != Vector3.ZERO:
		head_target.rotation = bd.head_rotation
	if bd.left_arm_magnet_position is Vector3 and bd.left_arm_magnet_position != Vector3.ZERO:
		left_arm_magnet.position = bd.left_arm_magnet_position
	if bd.right_arm_magnet_position is Vector3 and bd.right_arm_magnet_position != Vector3.ZERO:
		right_arm_magnet.position = bd.right_arm_magnet_position
	if bd.left_leg_magnet_position is Vector3 and bd.left_leg_magnet_position != Vector3.ZERO:
		left_leg_magnet.position = bd.left_leg_magnet_position
	if bd.right_leg_magnet_position is Vector3 and bd.right_leg_magnet_position != Vector3.ZERO:
		right_leg_magnet.position = bd.right_leg_magnet_position
	if bd.left_hand_rotation is Vector3 and bd.left_hand_rotation != Vector3.ZERO:
		left_hand_target.rotation = bd.left_hand_rotation
	if bd.right_hand_rotation is Vector3 and bd.right_hand_rotation != Vector3.ZERO:
		right_hand_target.rotation = bd.right_hand_rotation
	if bd.left_foot_rotation is Vector3 and bd.left_foot_rotation != Vector3.ZERO:
		left_foot_target.rotation = bd.left_foot_rotation
	if bd.right_foot_rotation is Vector3 and bd.right_foot_rotation != Vector3.ZERO:
		right_foot_target.rotation = bd.right_foot_rotation


func _deferred_init():
	if int(name) == multiplayer.get_unique_id():
		is_local_client = true
		camera_controller.deferred_init()
		_init_audio()
		hud_manager.local_player = self
		add_to_group(UtilsConstants.GROUPS["LocalPlayer"])
		if debug_netcode_metrics:
			_dbg_open_log()
			NetworkRollback.before_loop.connect(_dbg_before_loop)
			NetworkRollback.after_loop.connect(_dbg_after_loop)
	else:
		hud_manager.hide_all()


## The HUD holds a bare ref to the local player (hud_manager.local_player). Clear it on
## teardown so a stale read fails as a clean null (see RidingHUDState.Enter) rather than a
## "previously freed" crash. `== self` keeps this order-independent with the next player's spawn.
func _exit_tree():
	if is_local_client and hud_manager.local_player == self:
		hud_manager.local_player = null
	if _dbg_log_file != null:
		_dbg_log_file.close()


func _init_audio():
	if !audio_manager:
		return
	gearing_controller.rpm_updated.connect(_on_rpm_updated)

	# TODO - add clunk sound when changing gears
	audio_manager.play_revs(bike_definition)


func _init_controller_handlers():
	gearing_controller.gear_changed.connect(_on_gear_changed)
	trick_controller.trick_started.connect(_on_trick_started)
	trick_controller.trick_ended.connect(_on_trick_ended)


#endregion


#region handlers
func _on_rpm_updated(new_rpm_ratio: float):
	if !audio_manager:
		return
	audio_manager.update_revs_rpm(bike_definition, new_rpm_ratio)


func _on_gear_changed(new_gear: int):
	DebugUtils.DebugMsg("Gear: %d" % new_gear, OS.has_feature("debug"))
	if is_local_client and audio_manager:
		audio_manager.play_clunk_gear_change()
		# audio_manager.play_mouse_click()


func _on_trick_started(trick_type: TrickController.Trick):
	DebugUtils.DebugMsg(
		"Trick Started: %s" % TrickController.trick_to_str(trick_type), OS.has_feature("debug")
	)


func _on_trick_ended(trick_type: TrickController.Trick):
	DebugUtils.DebugMsg(
		"Trick Ended: %s" % TrickController.trick_to_str(trick_type),
		OS.has_feature("debug") and false
	)

	if (
		is_local_client
		and audio_manager
		and (
			trick_type
			not in [
				TrickController.Trick.NONE,
				TrickController.Trick.WHEELIE_SITTING,
				TrickController.Trick.WHEELIE_MOD,
				TrickController.Trick.STOPPIE
			]
		)
	):
		audio_manager.play_ding()


#endregion

#region public api


func update_skins(new_bike_def: BikeSkinDefinition, new_char_def: CharacterSkinDefinition):
	bike_definition = new_bike_def
	character_definition = new_char_def
	_init_mesh()
	_init_collision_shape()
	_init_ik()
	_init_raycasts()
	# AnimationController caches _bd + base pose positions in initialize(); re-run so they
	# pick up the new bike's wheel positions, chest/butt offsets, etc.
	animation_controller.initialize()
	# Flush any active anim layers / procedural pose deltas accumulated against the old bike,
	# otherwise stale offsets stay baked into the IK markers until the next respawn.
	for child in controllers_node.get_children():
		if child.has_method("do_reset"):
			child.do_reset()
	# Restart engine sound so the new bike's EngineSoundEvent gets its rpm_curve/pitch
	# range assigned — otherwise the next update_revs_rpm tick null-derefs rpm_curve.
	if is_local_client and audio_manager:
		audio_manager.play_revs(bike_definition)


## Resolve which transform the next respawn should use, consuming the one-shot.
## Snapshotted into _respawn_target when the respawn is anchored — consuming it inside
## do_respawn() would make resim re-applies fall back to the wrong transform.
func _pick_respawn_target() -> Transform3D:
	if rb_respawn_transform_oneshot != Transform3D():
		var target := rb_respawn_transform_oneshot
		rb_respawn_transform_oneshot = Transform3D()
		return target
	if rb_respawn_transform != Transform3D():
		return rb_respawn_transform
	return get_parent().global_transform


## Rollback-safe part of a respawn — only synced state (or vars feeding it), so it can
## be re-applied when netfox resimulates the respawn tick.
func _apply_respawn_state():
	global_transform = _respawn_target
	velocity = Vector3.ZERO
	# A crash voids only what the in-progress combo earned — boost banked by earlier
	# completed combos is yours to keep. Must run BEFORE the do_reset() loop below, which
	# clears the combo state this reads.
	boost_controller.apply_crash_void(trick_controller.combo_boost_earned)
	is_crashed = false
	for child in controllers_node.get_children():
		if !child.has_method("do_reset"):
			continue
		child.do_reset()


## Rammed by another racer (AI or human) — the one who hit us detected it and
## broadcast, since we never see that collision ourselves.
func on_crash():
	# Already down (two riders piling in, or the RPC racing our own crash) —
	# re-triggering would restart the ragdoll on top of itself.
	if is_crashed:
		return
	crash_controller.trigger_crash()


func do_respawn():
	_apply_respawn_state()
	if animation_controller:
		animation_controller.stop_ragdoll()
	if is_local_client and audio_manager:
		audio_manager.play_revs(bike_definition)
	# Re-spawn the bike mesh so any handlebar/wheel children moved by ragdoll/anim are
	# back to base, then re-init IK so its targets snap to the fresh markers.
	_init_mesh()
	_init_ik()
	hud_manager.go_to_riding_hud()
	respawned.emit()


#endregion


#region netcode metrics probe
## Open the Desktop log for this instance — _server when hosting, _client otherwise. Best-effort
## (mirrors the warmup marker write): a failed open just disables file logging, stdout still runs.
func _dbg_open_log() -> void:
	var suffix := "server" if multiplayer.is_server() else "client"
	var path := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP).path_join("netcode_metrics_%s.txt" % suffix)
	_dbg_log_file = FileAccess.open(path, FileAccess.WRITE)
	if _dbg_log_file == null:
		DebugUtils.DebugErrMsg("[netcode] could not open log at %s" % path)
		return
	DebugUtils.DebugMsg("[netcode] logging to %s" % path)


## Snapshot our predicted state right before netfox re-applies authoritative state this loop.
func _dbg_before_loop() -> void:
	_dbg_pre_speed = movement_controller.speed
	_dbg_pre_vel_len = velocity.length()


## Log how far reconciliation yanked speed/velocity. Under steady input these should be ~0;
## a large recurring jump is the rubber-band. resim = ticks netfox resimulated this loop.
func _dbg_after_loop() -> void:
	var d_speed := absf(movement_controller.speed - _dbg_pre_speed)
	var d_vel := absf(velocity.length() - _dbg_pre_vel_len)
	if d_speed < 0.5 and d_vel < 0.5:
		return
	var line := (
		"[netcode] tick=%d resim=%d | speed %.1f (Δ%.1f) | vel %.1f (Δ%.1f) | rpm %.2f"
		% [
			NetworkTime.tick,
			NetworkPerformance.get_rollback_ticks(),
			movement_controller.speed, d_speed,
			velocity.length(), d_vel,
			gearing_controller.get_rpm_ratio(),
		]
	)
	DebugUtils.DebugMsg(line)
	if _dbg_log_file != null:
		_dbg_log_file.store_line(line)
		_dbg_log_file.flush()


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if movement_controller == null:
		issues.append("movement_controller must not be empty")
	if input_controller == null:
		issues.append("input_controller must not be empty")
	if animation_controller == null:
		issues.append("animation_controller must not be empty")
	if gearing_controller == null:
		issues.append("gearing_controller must not be empty")
	if trick_controller == null:
		issues.append("trick_controller must not be empty")
	if crash_controller == null:
		issues.append("crash_controller must not be empty")
	if camera_controller == null:
		issues.append("camera_controller must not be empty")
	if boost_controller == null:
		issues.append("boost_controller must not be empty")
	if bike_definition == null:
		issues.append("bike_definition must not be empty")
	if collision_shape_3d == null:
		issues.append("collision_shape_3d must not be empty")
	if butt_target == null:
		issues.append("butt_target must not be empty")
	if left_hand_target == null:
		issues.append("left_hand_target must not be empty")
	if right_hand_target == null:
		issues.append("right_hand_target must not be empty")
	if left_foot_target == null:
		issues.append("left_foot_target must not be empty")
	if right_foot_target == null:
		issues.append("right_foot_target must not be empty")
	if chest_target == null:
		issues.append("chest_target must not be empty")
	if head_target == null:
		issues.append("head_target must not be empty")
	if left_arm_magnet == null:
		issues.append("left_arm_magnet must not be empty")
	if right_arm_magnet == null:
		issues.append("right_arm_magnet must not be empty")
	if left_leg_magnet == null:
		issues.append("left_leg_magnet must not be empty")
	if right_leg_magnet == null:
		issues.append("right_leg_magnet must not be empty")
	return issues
