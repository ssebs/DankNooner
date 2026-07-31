## Kinematic AI rider chassis — it just moves and collides. No netfox rollback,
## no input simulation, no bike physics. The server simulates; clients are
## passive and receive `transform` + `npc_state` via the child
## MultiplayerSynchronizer.
##
## The BEHAVIOR lives in the child StateMachine (idle / race / traffic) — those
## states own the physics tick and call the helpers below. A manager moves a
## freshly spawned rider into its behavior state.
##
## Steering follows the road-generator lane curves (via RoadLaneAgent), not a
## navmesh: the bot reads a point ahead along its current RoadLane, which
## auto-wraps to lane_next — so it rides the road's own line and never
## corner-cuts. Checkpoints only score laps / set respawns (see RaceTask).
##
## VisualRoot is yawed 180° (matching the player scene), so the bike front is
## entity -Z; steering yaws the body to face velocity with -Z.
@tool
class_name NPCRiderEntity extends CharacterBody3D

## Another racer rammed us — they detected it, because slide collisions only
## report what YOU moved into. The behavior state decides what it means: traffic
## wipes out, race bots (nobody connected) shrug it off.
signal hit_by_racer(hitter: Node3D)

enum NPCState { RIDING, WHEELIE, CRASHED, FINISHED }
## What this chassis is wearing. CAR spawns no bike mesh, no character, no IK,
## and no name label — see _enter_tree.
enum VehicleType { BIKE, CAR }

## Set by the spawning manager BEFORE add_child — _enter_tree reads it.
@export var vehicle_type: VehicleType = VehicleType.BIKE
@export var car_definition: CarSkinDefinition
@export var bike_definition: BikeSkinDefinition
@export var character_definition: CharacterSkinDefinition
@export var animation_controller: NPCAnimationController
## Behavior states live here — managers move the rider with request_state_change.
@export var state_machine: StateMachine
@export var move_speed: float = 35.0
## Per-rider speed spread (fraction of move_speed), seeded off the node name so
## riders don't all travel at exactly the same speed.
@export var speed_variance: float = 0.1
## Speed ramp rates (units/s^2) — accel when speeding up, braking when slowing.
@export var acceleration: float = 64.0
@export var braking: float = 40.0
## Speed floor through the sharpest turns. The bot eases down toward this as the
## road bends ahead, then accelerates back to move_speed as it straightens.
@export var min_turn_speed: float = 8.0
## Exponent on the road's bend — higher brakes harder for the same corner
## (1 = linear, so even gentle turns shed speed as this climbs).
@export var turn_sharpness: float = 4.0
## How far ahead along the nav path (metres) to read the road's bend when
## picking corner speed — larger = brakes earlier for upcoming turns.
@export var turn_lookahead: float = 12.0
@export var turn_speed: float = 4.0
## How many seconds of travel ahead to place the steering target on the lane
## curve — larger smooths the line, smaller hugs it. Clamped to a sane range.
@export var steer_lookahead_time: float = 0.25
@export var min_steer_lookahead: float = 3.0
@export var max_steer_lookahead: float = 12.0
## Per-bot lateral wander off the lane centreline so they don't trace one line.
@export var max_line_offset: float = 0.7

const GRAVITY: float = 30.0

@onready var visual_root: Node3D = %VisualRoot
@onready var name_label: Label3D = %NameLabel
@onready var collision_shape_3d: CollisionShape3D = $CollisionShape3D

## Only the half this vehicle actually uses survives — see _enter_tree.
var bike_skin: BikeSkin
var character_skin: CharacterSkin
var car_skin: CarSkin

## The level's RoadManager — set by the spawning manager before add_child so the
## lane agent can find its lanes. Riding follows those lanes.
var road_manager: RoadManager

## Synced to clients via MultiplayerSynchronizer (server authority).
var npc_state: NPCState = NPCState.RIDING

var username: String:
	set(v):
		username = v
		if is_node_ready():
			name_label.text = username

## Server sets this to start/stop the bot riding along its lane.
var driving: bool = false
## Current horizontal speed magnitude, ramped toward the turn-scaled target.
var current_speed: float = 0.0
## Lane-curve follower — created in _ready once road_manager is known.
var lane_agent: RoadLaneAgent
## Fixed lateral offset off the centreline, for line variety between bots.
var line_offset: float = 0.0

## Stable per-rider scale on move_speed (see speed_variance).
var _speed_scale: float = 1.0


## Drop the skins this vehicle doesn't wear — a car keeps CarSkin, a bike keeps
## BikeSkin + CharacterSkin.
##
## This can't wait for _ready: all three skins build their own mesh in their own
## _ready, and a child's _ready runs BEFORE its parent's, so by then they'd
## already exist. The spawning manager sets vehicle_type before add_child, so
## we know which is which this early. @onready vars and %UniqueName aren't
## resolved yet — direct paths only.
func _enter_tree() -> void:
	var visuals := get_node("VisualRoot")
	bike_skin = visuals.get_node("BikeSkin")
	character_skin = visuals.get_node("CharacterSkin")
	car_skin = visuals.get_node("CarSkin")

	# Editing the scene keeps every skin. Freeing one here would delete it out of
	# npc_rider_entity.tscn the moment you saved — _init_mesh hides it instead.
	if Engine.is_editor_hint():
		return

	if vehicle_type == VehicleType.CAR:
		_drop_skin(bike_skin)
		_drop_skin(character_skin)
		bike_skin = null
		character_skin = null
	else:
		_drop_skin(car_skin)
		car_skin = null


func _ready():
	# Same shape as PlayerEntity._ready: definitions → mesh → collision up front so
	# the scene previews correctly in-editor, then bail before anything that needs
	# a spawning manager (road_manager is null until one runs).
	_init_mesh()
	_init_collision_shape()

	if Engine.is_editor_hint():
		return

	# A car has no rider to name. Written on both paths — a hidden label could
	# otherwise have been saved into the scene by an earlier editor session.
	name_label.visible = vehicle_type != VehicleType.CAR
	if vehicle_type != VehicleType.CAR:
		# Runtime only, unlike PlayerEntity: IKTargets is a child of VisualRoot
		# here, so running IK in-editor re-poses markers that live in the scene.
		animation_controller.initialize()
		name_label.text = username

	add_to_group(UtilsConstants.GROUPS["Racers"])
	set_multiplayer_authority(1)

	lane_agent = RoadLaneAgent.new()
	lane_agent.road_manager_path = road_manager.get_path()
	# Don't auto-free the bot when its lane rebuilds — the manager owns its life.
	lane_agent.auto_register = false
	add_child(lane_agent)
	lane_agent.assign_nearest_lane()

	# Per-bot variety: a lateral offset + a speed scale, seeded off the (unique)
	# node name so both are stable and differ between bots.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	line_offset = rng.randf_range(-max_line_offset, max_line_offset)
	_speed_scale = rng.randf_range(1.0 - speed_variance, 1.0 + speed_variance)

	# Clients never simulate — they just play back the synced transform.
	if !multiplayer.is_server():
		state_machine.set_physics_process(false)


#region Steering helpers (called by the behavior states, server-side)


## Point this far ahead along the current lane curve, nudged sideways by this
## rider's fixed line offset. Advances current_lane across segment boundaries.
func lane_point_ahead(dist: float) -> Vector3:
	# a.cross(UP) is always horizontal, so no need to flatten the facing first.
	var right := (-global_transform.basis.z).cross(Vector3.UP).normalized()
	return lane_agent.move_along_lane(dist) + right * line_offset


## This rider's flat-out speed — move_speed with its personal variance applied.
func cruise_speed() -> float:
	return move_speed * _speed_scale


## Corner-aware target speed: reads the lane's bend over the next
## `turn_lookahead` metres, sampled along the lane curve (test_move_along_lane
## doesn't advance the lane). Compare the road's heading over the near half of
## the window vs the far half: straight -> cruise, a bend eases toward
## min_turn_speed. Because we look ahead, the bot brakes BEFORE the apex and
## accelerates back out as the road straightens.
func lane_speed() -> float:
	var mid := lane_agent.test_move_along_lane(turn_lookahead)
	var far := lane_agent.test_move_along_lane(turn_lookahead * 2.0)
	var lead := mid - global_position
	var trail := far - mid
	lead.y = 0.0
	trail.y = 0.0
	var alignment := 1.0
	if lead.length_squared() > 0.01 and trail.length_squared() > 0.01:
		alignment = clampf(lead.normalized().dot(trail.normalized()), 0.0, 1.0)
	return lerpf(min_turn_speed, cruise_speed(), pow(alignment, turn_sharpness))


## How far ahead to place the steering target at the current speed.
func steer_lookahead() -> float:
	return clampf(current_speed * steer_lookahead_time, min_steer_lookahead, max_steer_lookahead)


## Ramp toward target_speed and point the horizontal velocity at target.
func steer_toward(target: Vector3, target_speed: float, delta: float) -> void:
	var dir := target - global_position
	dir.y = 0.0
	dir = dir.normalized()
	var rate := acceleration if target_speed > current_speed else braking
	current_speed = move_toward(current_speed, target_speed, rate * delta)
	velocity.x = dir.x * current_speed
	velocity.z = dir.z * current_speed


## Decay horizontal velocity — not driving, crashed, or finished.
func coast_to_stop(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, braking * delta)
	velocity.z = move_toward(velocity.z, 0.0, braking * delta)
	current_speed = Vector2(velocity.x, velocity.z).length()


func apply_gravity_and_move(delta: float) -> void:
	velocity.y -= GRAVITY * delta
	move_and_slide()
	_face_velocity(delta)


## Nearest racer within range + forward cone that is slower than us — the one
## worth passing / tucking in behind. Null if the road ahead is clear. Scans
## humans too.
func nearest_racer_ahead(detect_range: float, detect_angle: float) -> Node3D:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var best: Node3D = null
	var best_dist := detect_range
	for racer in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["Racers"]):
		if racer == self:
			continue
		var to: Vector3 = racer.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist < 0.5 or dist > best_dist:
			continue
		if forward.dot(to / dist) < detect_angle:
			continue
		if horizontal_speed(racer) >= current_speed - 1.0:
			continue
		best = racer
		best_dist = dist
	return best


## Horizontal speed of any racer (NPC or player) — both are CharacterBody3D.
func horizontal_speed(racer: Node3D) -> float:
	var v: Vector3 = racer.velocity
	return Vector2(v.x, v.z).length()


#endregion


#region AI control (server-side, called by the managers)


## Cosmetic only — the bot stops and the rig reads as wiped out (no ragdoll v1).
## The owning manager owns the recovery timer + teleport.
func crash() -> void:
	npc_state = NPCState.CRASHED
	velocity = Vector3.ZERO


## Called by whoever rode into us (see CrashController).
func report_hit(hitter: Node3D) -> void:
	hit_by_racer.emit(hitter)


## Cosmetic stub — v1 has no trick variety; kept as the hook for it.
func wheelie() -> void:
	npc_state = NPCState.WHEELIE


func stop_wheelie() -> void:
	npc_state = NPCState.RIDING


func finish() -> void:
	npc_state = NPCState.FINISHED
	driving = false


## Teleport (crash recovery / grid placement). Resets driving state.
func teleport_to(pos: Vector3, basis: Basis) -> void:
	global_transform = Transform3D(basis, pos)
	velocity = Vector3.ZERO
	current_speed = 0.0
	npc_state = NPCState.RIDING
	# Position jumped — re-latch to the nearest lane from here.
	lane_agent.assign_nearest_lane()


#endregion


func _face_velocity(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length_squared() < 0.25:
		return
	# -Z faces the travel direction (bike front is -Z, see class docstring).
	var target_yaw := atan2(-horizontal.x, -horizontal.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)


## Set definitions and apply mesh/colors — PlayerEntity._init_mesh, with a car
## branch. Runs in-editor too, so swapping car_definition / bike_definition on the
## scene previews straight away instead of showing whatever bike_skin.tscn and
## car_skin.tscn happen to default to.
##
## In-editor every skin is still present (see _enter_tree), so the unused half is
## hidden rather than freed. Visibility is written on every path, so a `visible`
## flag saved into the scene can never leak onto the wrong vehicle.
func _init_mesh() -> void:
	var editing := Engine.is_editor_hint()
	if vehicle_type == VehicleType.CAR:
		car_skin.visible = true
		car_skin.skin_definition = car_definition
		car_skin._apply_definition()
		if editing:
			bike_skin.visible = false
			character_skin.visible = false
		return

	bike_skin.visible = true
	character_skin.visible = true
	bike_skin.skin_definition = bike_definition
	bike_skin._apply_definition()
	character_skin.skin_definition = character_definition
	character_skin.apply_definition()
	if editing:
		car_skin.visible = false


## free(), not queue_free() — a deferred free still lets the node's _ready run and
## build the skin we're dropping.
func _drop_skin(skin: Node) -> void:
	skin.get_parent().remove_child(skin)
	skin.free()


## The scene's capsule fits a bike; a car needs its own box. Same four lines as
## PlayerEntity._init_collision_shape(), off whichever definition is in play.
func _init_collision_shape() -> void:
	# Both definitions expose the same four collision fields; nothing else is shared.
	var definition: Resource = (
		car_definition if vehicle_type == VehicleType.CAR else bike_definition
	)
	collision_shape_3d.shape = definition.collision_shape
	collision_shape_3d.position = definition.collision_position_offset
	collision_shape_3d.rotation_degrees = definition.collision_rotation_offset_degrees
	collision_shape_3d.scale = definition.collision_scale_multiplier


func _get_configuration_warnings() -> PackedStringArray:
	var issues := PackedStringArray()
	if vehicle_type == VehicleType.CAR:
		if car_definition == null:
			issues.append("car_definition must not be empty when vehicle_type is CAR")
	else:
		if bike_definition == null:
			issues.append("bike_definition must not be empty")
		if character_definition == null:
			issues.append("character_definition must not be empty")
	if animation_controller == null:
		issues.append("animation_controller must not be empty")
	if state_machine == null:
		issues.append("state_machine must not be empty")
	return issues
