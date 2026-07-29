@tool
## Racing behavior for NPCRiderEntity: follow the lane at corner-aware speed,
## change lanes to pass slower racers, and merge off a lane that dead-ends.
## NPCRaceManager toggles `npc.driving` and owns the crash/respawn timers.
class_name NPCRaceState extends State

enum Difficulty { EASY, MEDIUM, HARD }

@export var npc: NPCRiderEntity
## Scales speed / corner carry / overtaking aggression off the entity's base
## tuning. MEDIUM leaves it untouched. Applied once on Enter.
@export var difficulty: Difficulty = Difficulty.MEDIUM
## Overtaking: a racer within this range and forward cone (dot >= detect_angle)
## and slower than us counts as a blocker to pass.
@export var overtake_detect_range: float = 9.0
@export var overtake_detect_angle: float = 0.6
## Seconds between lane changes — stops the bot ping-ponging between lanes.
@export var lane_change_cooldown_time: float = 1.2
## Master switch for lane changes + line offset. Off = pure single-lane follow
## (the stable baseline) — flip off to isolate lane-change issues.
@export var enable_overtaking: bool = true

## The lane (F-index) this bot drifts back to when nothing's blocking it.
var _preferred_lane_index: int = 1  # middle lane
## Counts down after a lane change (see lane_change_cooldown_time).
var _lane_change_cd: float = 0.0


func Enter(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
	_apply_difficulty()
	if !enable_overtaking:
		npc.line_offset = 0.0


func Physics_Update(delta: float):
	if Engine.is_editor_hint():
		return

	# Lanes may not have been built yet at spawn, or we just teleported — grab
	# the nearest lane before we can steer. Self-heals crash-respawns too.
	if npc.driving and !is_instance_valid(npc.lane_agent.current_lane):
		npc.lane_agent.assign_nearest_lane()

	var can_drive := (
		npc.driving
		and is_instance_valid(npc.lane_agent.current_lane)
		and npc.npc_state != NPCRiderEntity.NPCState.CRASHED
		and npc.npc_state != NPCRiderEntity.NPCState.FINISHED
	)
	if can_drive:
		_drive(delta)
	else:
		npc.coast_to_stop(delta)

	npc.apply_gravity_and_move(delta)


## Scale the entity's base tuning for this difficulty tier. MEDIUM is a no-op.
func _apply_difficulty() -> void:
	match difficulty:
		Difficulty.EASY:
			npc.move_speed *= 0.82
			npc.min_turn_speed *= 0.85
			lane_change_cooldown_time *= 1.6
		Difficulty.HARD:
			npc.move_speed *= 1.12
			npc.min_turn_speed *= 1.15
			lane_change_cooldown_time *= 0.6
			npc.max_line_offset *= 0.5
			# The offset was already rolled in _ready off the old maximum.
			npc.line_offset = clampf(npc.line_offset, -npc.max_line_offset, npc.max_line_offset)
		Difficulty.MEDIUM:
			pass


func _drive(delta: float) -> void:
	var forward := -npc.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)

	# Pick which lane to be in. Merging off a dead-ending lane wins over
	# everything (else the bot runs off the road where it narrows); otherwise
	# dodge a slower racer ahead, else drift back to the home lane.
	var blocker: Node3D = null
	if enable_overtaking:
		_lane_change_cd = maxf(0.0, _lane_change_cd - delta)
		blocker = npc.nearest_racer_ahead(overtake_detect_range, overtake_detect_angle)
		if !_merge_if_lane_ends():
			_update_lane_choice(blocker, forward, right)

	var target := npc.lane_point_ahead(npc.steer_lookahead())
	var target_speed := npc.lane_speed()
	# Couldn't get past the blocker this tick — match its speed so we tuck in
	# behind instead of ramming it.
	if blocker != null:
		target_speed = minf(target_speed, npc.horizontal_speed(blocker))
	npc.steer_toward(target, target_speed, delta)


## The road narrows (e.g. 3->2 lanes): our lane dead-ends with no lane_next, so
## merge to a lane that continues before we run off the end into the void.
## Returns true if a merge was needed — the caller skips its normal lane pick.
func _merge_if_lane_ends() -> bool:
	var proximity := maxf(6.0, npc.current_speed * 0.4)
	if !npc.lane_agent.close_to_lane_end(proximity, RoadLaneAgent.MoveDir.FORWARD):
		return false
	# find_continued_lane returns a signed lane count to a lane that keeps going;
	# feed it straight to change_lane (which moves abs() lanes in that direction).
	var cont := npc.lane_agent.find_continued_lane(
		RoadLaneAgent.LaneChangeDir.LEFT, RoadLaneAgent.MoveDir.FORWARD
	)
	if cont == 0:
		cont = npc.lane_agent.find_continued_lane(
			RoadLaneAgent.LaneChangeDir.RIGHT, RoadLaneAgent.MoveDir.FORWARD
		)
	if cont != 0:
		npc.lane_agent.change_lane(cont)
		_lane_change_cd = lane_change_cooldown_time
	else:
		# Nothing linked continues — grab whatever lane is nearest to recover.
		npc.lane_agent.assign_nearest_lane()
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
		if npc.lane_agent.change_lane(side) == OK or npc.lane_agent.change_lane(-side) == OK:
			_lane_change_cd = lane_change_cooldown_time
		return

	# Nothing ahead — ease back toward the preferred lane (change_lane +1 = right,
	# which is the next-higher F-index; see the lane naming in the racetrack).
	var toward := signi(_preferred_lane_index - _lane_index())
	if toward != 0 and npc.lane_agent.change_lane(toward) == OK:
		_lane_change_cd = lane_change_cooldown_time


## +1 (change right) or -1 (change left) toward whichever side has fewer racers
## ahead of us — the emptier side to overtake into. Ties go left.
func _pick_overtake_side(forward: Vector3, right: Vector3) -> int:
	var left_count := 0
	var right_count := 0
	for racer in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["Racers"]):
		if racer == npc:
			continue
		var to: Vector3 = racer.global_position - npc.global_position
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


## The forward-lane index (F0/F1/F2) of the current lane, read from its node name.
func _lane_index() -> int:
	var lane_name := String(npc.lane_agent.current_lane.name)
	var f := lane_name.find("F")
	if f == -1:
		return 0
	return lane_name.substr(f + 1, 1).to_int()


func _get_configuration_warnings() -> PackedStringArray:
	var issues := PackedStringArray()
	if npc == null:
		issues.append("npc must not be empty")
	return issues
