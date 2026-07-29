## Kinematic AI race rider — it just moves and collides. No netfox rollback,
## no input simulation, no bike physics. The server simulates (NPCRaceManager
## toggles `driving` and owns crash/respawn timers); clients are passive and
## receive `transform` + `npc_state` via the child MultiplayerSynchronizer.
##
## Steering follows the road-generator lane curves (via RoadLaneAgent), not a
## navmesh: the bot reads a point ahead along its current RoadLane, which
## auto-wraps to lane_next — so it rides the road's own line and never
## corner-cuts. Checkpoints only score laps / set respawns (see RaceTask).
##
## VisualRoot is yawed 180° (matching the player scene), so the bike front is
## entity -Z; steering yaws the body to face velocity with -Z.
class_name NPCRiderEntity extends CharacterBody3D

enum NPCState { RIDING, WHEELIE, CRASHED, FINISHED }
enum Difficulty { EASY, MEDIUM, HARD }

## Scales speed / corner carry / overtaking aggression off the base tuning below.
## MEDIUM leaves the exported defaults untouched. Applied once in _ready.
@export var difficulty: Difficulty = Difficulty.MEDIUM
@export var bike_definition: BikeSkinDefinition
@export var character_definition: CharacterSkinDefinition
@export var animation_controller: NPCAnimationController
@export var move_speed: float = 35.0
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
## Overtaking: a racer within this range and forward cone (dot >= detect_angle)
## and slower than us counts as a blocker to pass.
@export var overtake_detect_range: float = 9.0
@export var overtake_detect_angle: float = 0.6
## Seconds between lane changes — stops the bot ping-ponging between lanes.
@export var lane_change_cooldown_time: float = 1.2
## Per-bot lateral wander off the lane centreline so they don't trace one line.
@export var max_line_offset: float = 0.7
## Master switch for lane changes + line offset. Off = pure single-lane follow
## (the stable baseline) — flip off to isolate lane-change issues.
@export var enable_overtaking: bool = true

const GRAVITY: float = 30.0

@onready var visual_root: Node3D = %VisualRoot
@onready var bike_skin: BikeSkin = %BikeSkin
@onready var character_skin: CharacterSkin = %CharacterSkin
@onready var name_label: Label3D = %NameLabel

## The level's RoadManager — set by NPCRaceManager before add_child so the lane
## agent can find its lanes. Riding follows those lanes.
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
var _speed: float = 0.0
## Lane-curve follower — created in _ready once road_manager is known.
var _lane_agent: RoadLaneAgent
## The lane (F-index) this bot drifts back to when nothing's blocking it.
var _preferred_lane_index: int = 0
## Fixed lateral offset off the centreline, for line variety between bots.
var _line_offset: float = 0.0
## Counts down after a lane change (see lane_change_cooldown_time).
var _lane_change_cd: float = 0.0


func _ready():
	bike_skin.skin_definition = bike_definition
	bike_skin._apply_definition()
	character_skin.skin_definition = character_definition
	character_skin.apply_definition()
	animation_controller.initialize()
	name_label.text = username

	add_to_group(UtilsConstants.GROUPS["Racers"])
	set_multiplayer_authority(1)
	apply_difficulty(difficulty)

	_lane_agent = RoadLaneAgent.new()
	_lane_agent.road_manager_path = road_manager.get_path()
	# Don't auto-free the bot when its lane rebuilds — NPCRaceManager owns its life.
	_lane_agent.auto_register = false
	add_child(_lane_agent)
	_lane_agent.assign_nearest_lane()

	# Per-bot line variety: a home lane + a small lateral offset, seeded off the
	# (unique) node name so it's stable and differs between bots.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	_preferred_lane_index = 1 # middle lane
	_line_offset = rng.randf_range(-max_line_offset, max_line_offset)


func _physics_process(delta: float):
	if !multiplayer.is_server():
		return

	# Lanes may not have been built yet at spawn, or we just teleported — grab
	# the nearest lane before we can steer. Self-heals crash-respawns too.
	if driving and !is_instance_valid(_lane_agent.current_lane):
		_lane_agent.assign_nearest_lane()

	var can_drive := (
		driving
		and is_instance_valid(_lane_agent.current_lane)
		and npc_state != NPCState.CRASHED
		and npc_state != NPCState.FINISHED
	)
	if can_drive:
		var forward := -global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := forward.cross(Vector3.UP)

		# Pick which lane to be in. Merging off a dead-ending lane wins over
		# everything (else the bot runs off the road where it narrows); otherwise
		# dodge a slower racer ahead, else drift back to the home lane.
		var blocker: Node3D = null
		var line_off := 0.0
		if enable_overtaking:
			_lane_change_cd = maxf(0.0, _lane_change_cd - delta)
			blocker = _nearest_blocker_ahead(forward)
			if !_merge_if_lane_ends():
				_update_lane_choice(blocker, forward, right)
			line_off = _line_offset

		# Steer toward a point a little ahead along the (possibly just-changed)
		# lane curve, nudged by this bot's fixed offset. move_along_lane advances
		# current_lane across segment boundaries, so the bot follows the road's
		# own line and wraps onto lane_next without any pathfinding.
		var steer_ahead := clampf(
			_speed * steer_lookahead_time, min_steer_lookahead, max_steer_lookahead
		)
		var target := _lane_agent.move_along_lane(steer_ahead) + right * line_off
		var dir := target - global_position
		dir.y = 0.0
		dir = dir.normalized()

		# Corner speed reads the lane's bend over the next `turn_lookahead` metres,
		# sampled along the lane curve (test_move_along_lane doesn't advance the
		# lane). Compare the road's heading over the near half of the window vs the
		# far half: straight -> move_speed, a bend eases toward min_turn_speed.
		# Because we look ahead, the bot brakes BEFORE the apex and accelerates
		# back out as the road straightens.
		var mid := _lane_agent.test_move_along_lane(turn_lookahead)
		var far := _lane_agent.test_move_along_lane(turn_lookahead * 2.0)
		var lead := mid - global_position
		var trail := far - mid
		lead.y = 0.0
		trail.y = 0.0
		var alignment := 1.0
		if lead.length_squared() > 0.01 and trail.length_squared() > 0.01:
			alignment = clampf(lead.normalized().dot(trail.normalized()), 0.0, 1.0)
		var turn_factor := pow(alignment, turn_sharpness)
		var target_speed := lerpf(min_turn_speed, move_speed, turn_factor)
		# Couldn't get past the blocker this tick — match its speed so we tuck in
		# behind instead of ramming it.
		if blocker != null:
			target_speed = minf(target_speed, _horizontal_speed(blocker))
		var rate := acceleration if target_speed > _speed else braking
		_speed = move_toward(_speed, target_speed, rate * delta)

		velocity.x = dir.x * _speed
		velocity.z = dir.z * _speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, braking * delta)
		velocity.z = move_toward(velocity.z, 0.0, braking * delta)
		_speed = Vector2(velocity.x, velocity.z).length()

	velocity.y -= GRAVITY * delta
	move_and_slide()
	_face_velocity(delta)


#region AI control (server-side, called by NPCRaceManager)


## Scale the base tuning for a difficulty tier. MEDIUM is a no-op (keeps the
## exported defaults). Call before the bot starts riding.
func apply_difficulty(tier: Difficulty) -> void:
	match tier:
		Difficulty.EASY:
			move_speed *= 0.82
			min_turn_speed *= 0.85
			lane_change_cooldown_time *= 1.6
		Difficulty.HARD:
			move_speed *= 1.12
			min_turn_speed *= 1.15
			lane_change_cooldown_time *= 0.6
			max_line_offset *= 0.5
		Difficulty.MEDIUM:
			pass


## Cosmetic only — the bot stops and the rig reads as wiped out (no ragdoll v1).
## NPCRaceManager owns the recovery timer + teleport back to the respawn point.
func crash() -> void:
	npc_state = NPCState.CRASHED
	velocity = Vector3.ZERO


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
	_speed = 0.0
	npc_state = NPCState.RIDING
	# Position jumped — re-latch to the nearest lane from here.
	_lane_agent.assign_nearest_lane()


#endregion


#region Overtaking (server-side, lane changes on the road-generator lanes)


## The road narrows (e.g. 3->2 lanes): our lane dead-ends with no lane_next, so
## merge to a lane that continues before we run off the end into the void.
## Returns true if a merge was needed — the caller skips its normal lane pick.
func _merge_if_lane_ends() -> bool:
	var proximity := maxf(6.0, _speed * 0.4)
	if !_lane_agent.close_to_lane_end(proximity, RoadLaneAgent.MoveDir.FORWARD):
		return false
	# find_continued_lane returns a signed lane count to a lane that keeps going;
	# feed it straight to change_lane (which moves abs() lanes in that direction).
	var cont := _lane_agent.find_continued_lane(
		RoadLaneAgent.LaneChangeDir.LEFT, RoadLaneAgent.MoveDir.FORWARD
	)
	if cont == 0:
		cont = _lane_agent.find_continued_lane(
			RoadLaneAgent.LaneChangeDir.RIGHT, RoadLaneAgent.MoveDir.FORWARD
		)
	if cont != 0:
		_lane_agent.change_lane(cont)
		_lane_change_cd = lane_change_cooldown_time
	else:
		# Nothing linked continues — grab whatever lane is nearest to recover.
		_lane_agent.assign_nearest_lane()
	return true


## Move one lane toward the clearer side to pass a blocker, or drift back to the
## home lane when the road ahead is clear. No-op while the change is on cooldown.
func _update_lane_choice(blocker: Node3D, forward: Vector3, right: Vector3) -> void:
	if _lane_change_cd > 0.0:
		return

	if blocker != null:
		var side := _pick_overtake_side(forward, right)
		# Try the open side first; at an edge lane change_lane FAILs, so fall back
		# to the other side. If neither works we just tuck in behind (speed cap).
		if _lane_agent.change_lane(side) == OK or _lane_agent.change_lane(-side) == OK:
			_lane_change_cd = lane_change_cooldown_time
		return

	# Nothing ahead — ease back toward the preferred lane (change_lane +1 = right,
	# which is the next-higher F-index; see the lane naming in the racetrack).
	var idx := _lane_index()
	var toward := signi(_preferred_lane_index - idx)
	if toward != 0 and _lane_agent.change_lane(toward) == OK:
		_lane_change_cd = lane_change_cooldown_time


## Nearest racer ahead (within range + forward cone) that is slower than us —
## the one worth passing. Null if the road ahead is clear. Scans humans too.
func _nearest_blocker_ahead(forward: Vector3) -> Node3D:
	var best: Node3D = null
	var best_dist := overtake_detect_range
	for racer in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["Racers"]):
		if racer == self:
			continue
		var to: Vector3 = racer.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist < 0.5 or dist > best_dist:
			continue
		if forward.dot(to / dist) < overtake_detect_angle:
			continue
		if _horizontal_speed(racer) >= _speed - 1.0:
			continue
		best = racer
		best_dist = dist
	return best


## +1 (change right) or -1 (change left) toward whichever side has fewer racers
## ahead of us — the emptier side to overtake into. Ties go left.
func _pick_overtake_side(forward: Vector3, right: Vector3) -> int:
	var left_count := 0
	var right_count := 0
	for racer in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["Racers"]):
		if racer == self:
			continue
		var to: Vector3 = racer.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist < 0.5 or dist > overtake_detect_range:
			continue
		if forward.dot(to / dist) < 0.3:
			continue
		if right.dot(to) > 0.0:
			right_count += 1
		else:
			left_count += 1
	return 1 if right_count < left_count else -1


## Horizontal speed of any racer (NPC or player) — both are CharacterBody3D.
func _horizontal_speed(racer: Node3D) -> float:
	var v: Vector3 = racer.velocity
	return Vector2(v.x, v.z).length()


## The forward-lane index (F0/F1/F2) of the current lane, read from its node name.
func _lane_index() -> int:
	var lane_name := String(_lane_agent.current_lane.name)
	var f := lane_name.find("F")
	if f == -1:
		return 0
	return lane_name.substr(f + 1, 1).to_int()


#endregion


func _face_velocity(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length_squared() < 0.25:
		return
	# -Z faces the travel direction (bike front is -Z, see class docstring).
	var target_yaw := atan2(-horizontal.x, -horizontal.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)


func _get_configuration_warnings() -> PackedStringArray:
	var issues := PackedStringArray()
	if bike_definition == null:
		issues.append("bike_definition must not be empty")
	if character_definition == null:
		issues.append("character_definition must not be empty")
	if animation_controller == null:
		issues.append("animation_controller must not be empty")
	return issues
