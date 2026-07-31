@tool
## Racing behavior for NPCRiderEntity: follow the lane at corner-aware speed,
## change lanes to pass slower racers, and merge off a lane that dead-ends.
## NPCRaceManager toggles `npc.driving` and owns the crash/respawn timers.
class_name NPCRaceState extends State

## Wedged and making no progress — NPCRaceManager wipes the bot out and puts it back on
## its last checkpoint. Lane following is blind to level geometry: a graybox parked on the
## racing line, a pit wall, a barrier the lane network knows nothing about. Traffic has
## had this since day one; racers were the ones left leaning on a wall forever.
signal stuck

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
## Report stuck after covering less than stuck_min_progress metres over stuck_window
## seconds. Generous on purpose — a slow crawl out of a hairpin must not read as wedged.
@export var stuck_window: float = 3.0
@export var stuck_min_progress: float = 2.0

## Junction routing table — set by NPCRaceManager right after spawn, same as
## NPCTrafficState gets one. RoadContainer never links intersection lanes with a
## lane_next, so without this the bot dead-ends at every junction. Null is survivable
## (closed-loop tracks chain lane to lane), which is why the racetrack always worked.
var route_graph: TrafficRouteGraph
## Set alongside route_graph: picking the right junction exit needs to know which
## checkpoint we're heading for.
var race_task: RaceTask

## The lane (F-index) this bot drifts back to when nothing's blocking it.
var _preferred_lane_index: int = 1  # middle lane
## Counts down after a lane change (see lane_change_cooldown_time).
var _lane_change_cd: float = 0.0
var _stuck_timer: float = 0.0
var _stuck_anchor: Vector3


func Enter(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
	_apply_difficulty()
	if !enable_overtaking:
		npc.line_offset = 0.0
	_stuck_timer = 0.0
	_stuck_anchor = npc.global_position


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

	# Only while it's actually trying to move — sitting on the grid or waiting out the
	# countdown is not being stuck.
	if can_drive:
		_check_stuck(delta)


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
	# Lane-end handling runs whether or not overtaking is on — it's what carries the bot
	# through junctions and road narrowings, not a passing manoeuvre.
	var merged := _merge_if_lane_ends()

	var blocker: Node3D = null
	if enable_overtaking:
		_lane_change_cd = maxf(0.0, _lane_change_cd - delta)
		blocker = npc.nearest_racer_ahead(overtake_detect_range, overtake_detect_angle)
		if !merged:
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
	# close_to_lane_end is false whenever lane_next is set, so reaching here always means
	# the lane genuinely stops: a junction, or the road narrowing.
	if !npc.lane_agent.close_to_lane_end(proximity, RoadLaneAgent.MoveDir.FORWARD):
		return false
	# Junctions first — an intersection lane has no lane_next AND no sideways
	# continuation, so find_continued_lane below can't do anything with it.
	if _route_through_junction():
		return true
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


## Take an intersection exit. The road generator tags junction lanes but never links
## them, so the route graph is the only thing that knows what continues from here.
## Unlike traffic — which picks at random — a racer takes the exit whose far end sits
## nearest its next checkpoint. Greedy rather than a real search, but it's the difference
## between following the road and following the course.
##
## False means there's no junction here to route, and the caller falls back to merging.
func _route_through_junction() -> bool:
	if route_graph == null:
		return false
	var successors := route_graph.next_lanes(npc.lane_agent.current_lane)
	if successors.is_empty():
		return false

	var target: CheckPointMarker = null
	if race_task != null:
		target = race_task.get_target_checkpoint(int(npc.name))
	# Null on the grid, during the countdown, and after finishing — no course to follow
	# yet, so any continuation beats stopping dead in the intersection.
	if target == null:
		npc.lane_agent.assign_lane(successors.pick_random())
		return true

	var best: RoadLane = successors[0]
	var best_score := -INF
	for lane in successors:
		var score := _score_junction_exit(lane, npc.global_position, target.global_position)
		if score > best_score:
			best_score = score
			best = lane
	npc.lane_agent.assign_lane(best)
	return true


## Leaning on something the lane network can't see. Sampled over a window rather than
## per tick so a genuinely slow section never trips it.
func _check_stuck(delta: float) -> void:
	_stuck_timer += delta
	if _stuck_timer < stuck_window:
		return
	var progress := npc.global_position.distance_to(_stuck_anchor)
	_stuck_timer = 0.0
	_stuck_anchor = npc.global_position
	if progress < stuck_min_progress:
		stuck.emit()


## Score a junction exit. Higher is better. Two things decide it:
##
## 1. Does it go anywhere? A lane with no successors of its own is a dead end — the pit
##    lane, a service road — and the checkpoint is never down one. Heavily penalised
##    rather than banned, so a bot is never left with nothing to pick.
## 2. Does it head the right way? Scored on the direction from the junction toward the
##    checkpoint, not raw distance to the lane's end. A pit entrance can END closer to
##    the next checkpoint than the main road does while pointing straight at a wall.
func _score_junction_exit(lane: RoadLane, from: Vector3, target_pos: Vector3) -> float:
	var to_target := target_pos - from
	to_target.y = 0.0
	var to_lane := lane.get_lane_end() - from
	to_lane.y = 0.0
	if to_target.length_squared() < 0.01 or to_lane.length_squared() < 0.01:
		return 0.0
	var score := to_target.normalized().dot(to_lane.normalized())
	if route_graph.next_lanes(lane).is_empty():
		score -= 10.0
	return score


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
