@tool
## Free-roam traffic behavior: circulate the level's baked TrafficNetwork forever.
## Rides its lane on rails via a TrafficLaneFollower (random turn at each fork) with no
## physics, so speed is all it decides. Tucks in behind whatever is ahead, waits its
## turn at junctions, and reports crashes to NPCTrafficManager, which owns the recovery.
class_name NPCTrafficState extends State

## Hit another racer — the manager wipes the rider out, respawns it, and takes
## the racer we hit down with us if it's a player.
signal crashed(victim: Node3D)
## A player passed through our NearMissArea and out again without crashing.
signal near_missed(player: PlayerEntity)

@export var npc: NPCRiderEntity
## A racer within this far ahead on our lane path gets followed rather than passed
## (traffic doesn't overtake in v1). Must cover braking distance from cruise + the gap.
@export var follow_detect_range: float = 36.0
## Forward cone for players and race bots; traffic ahead comes off lane_riders instead.
@export var follow_detect_angle: float = 0.7
## Relative speed (m/s) that makes rider-to-rider contact an actual impact — riders
## queueing nose-to-tail brush at matched speed and shouldn't both wipe out for it.
@export var contact_min_speed_delta: float = 6.0
## Waited this long at a stop line, go anyway unless a conflicting turn is occupied. Breaks
## deadlocks the gate can't see.
@export var junction_timeout: float = 8.0
## Sat still this long counts as a full stop, at a STOP sign or before turning right on red.
@export var full_stop_time: float = 1.0

## Room a stopped queue leaves between riders, beyond both their half lengths.
const QUEUE_GAP := 1.5
## A stopped rider this far into our exit lane leaves no room past the box: our half
## length, the queue gap, its half length.
const EXIT_CLEARANCE := 2.0 * NPCRiderEntity.STOP_LINE_BUFFER + QUEUE_GAP
## Metres sideways per metre driven while easing into a new lane.
const LANE_CHANGE_SLOPE := 0.5

## Set by NPCTrafficManager on spawn, recovery and recycle, and by lane changes. Moving a rider
## drops its junction, or its stale arrival would hold that junction's conflicting turns forever.
var follower: TrafficLaneFollower:
	set(v):
		_leave_junction()
		_wait_time = 0.0
		_lane_shift = 0.0
		follower = v
## Set by NPCTrafficManager on spawn, indexed like TrafficNetworkData.junctions.
var junctions: Array[JunctionState]
## Set by NPCTrafficManager on spawn, indexed like TrafficNetworkData.lanes: the traffic on each.
var lane_riders: Array[Array]
## Set by NPCTrafficManager on spawn: every racer but traffic, refreshed by its LOD pass.
var other_racers: Array

# Lane we're listed under in lane_riders, -1 when none
var _lane := -1
# Turn lane we've been let onto, -1 when none
var _claimed := -1
# Junction whose arrival queue we're in
var _queued: JunctionState
var _wait_time := 0.0
var _stopped_time := 0.0
# Player inside NearMissArea -> its crash_count on the way in
var _passing: Dictionary[Node3D, int] = {}
# Sideways offset off our lane left by a lane change, eased out as we drive
var _lane_shift := 0.0
var _next_lane_check_ms := 0


func Enter(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
	npc.contact_area.body_entered.connect(_on_contact)
	npc.contact_area.area_entered.connect(_on_contact)
	npc.near_miss_area.body_entered.connect(_on_near_miss_entered)
	npc.near_miss_area.body_exited.connect(_on_near_miss_exited)


func Exit(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
	npc.contact_area.body_entered.disconnect(_on_contact)
	npc.contact_area.area_entered.disconnect(_on_contact)
	npc.near_miss_area.body_entered.disconnect(_on_near_miss_entered)
	npc.near_miss_area.body_exited.disconnect(_on_near_miss_exited)
	_passing.clear()
	set_contact(false)
	_leave_junction()
	_track_lane(-1)


## NPCTrafficManager's LOD turns contact on only while a player is near.
func set_contact(on: bool) -> void:
	npc.contact_area.set_deferred("monitoring", on)
	npc.contact_area.set_deferred("monitorable", on)
	npc.near_miss_area.set_deferred("monitoring", on)


func Physics_Update(delta: float):
	if Engine.is_editor_hint():
		return
	if !npc.driving or npc.npc_state == NPCRiderEntity.NPCState.CRASHED:
		# A wreck mustn't hold the junction until the others time out
		_leave_junction()
		_wait_time = 0.0
		return

	if _claimed >= 0 and follower.lane != _claimed and follower.next_turn_lane() != _claimed:
		_leave_junction()
	var target_speed := npc.lane_speed(follower.point_ahead)
	# Close in on the rider ahead only as fast as we can still stop short of where it is now. It can
	# stop dead (a wreck does), so assuming it brakes like us chain-crashed whole queues.
	var blocker := _rider_ahead(follower)
	if blocker != null:
		# Takes effect next tick; this one still follows the old blocker
		_change_lane_around(blocker)
		target_speed = minf(target_speed, _follow_speed(npc, npc.global_position.distance_to(blocker.global_position)))
	target_speed = _gate(target_speed, delta)
	npc.ramp_speed(target_speed, delta)
	_stopped_time = _stopped_time + delta if is_zero_approx(npc.current_speed) else 0.0
	follower.advance(npc.current_speed * delta)
	_track_lane(follower.lane)
	_lane_shift = move_toward(_lane_shift, 0.0, npc.current_speed * delta * LANE_CHANGE_SLOPE)
	var lane_transform := follower.get_transform()
	var right := lane_transform.basis.x
	# Heading into the lane while still easing over
	var dir := (-lane_transform.basis.z - right * signf(_lane_shift) * LANE_CHANGE_SLOPE).normalized()
	npc.ride_to(lane_transform.origin + right * (npc.line_offset + _lane_shift), dir, delta)


## Nearest racer within follow_detect_range on `from`'s latched lane path, or null. Traffic comes off
## lane_riders, so no rider ever sweeps the whole pack. Other racers count if they're within the
## baker's vehicle width of the path and not oncoming, so one beside the lane doesn't stop us.
func _rider_ahead(from: TrafficLaneFollower) -> Node3D:
	var best: Node3D = null
	var best_dist := follow_detect_range
	var starts := from.lanes_ahead(follow_detect_range)
	for lane in starts:
		for other: NPCTrafficState in lane_riders[lane]:
			# Recovered onto another lane and not ticked since — skip is intentional
			if other.follower.lane != lane:
				continue
			# 0 is us
			var dist := starts[lane] + other.follower.offset
			if dist > 0.0 and dist < best_dist:
				best = other.npc
				best_dist = dist

	var forward := (-npc.global_transform.basis.z).slide(Vector3.UP).normalized()
	for racer in other_racers:
		# Despawned since the last LOD pass — skip is intentional
		if !is_instance_valid(racer):
			continue
		var to: Vector3 = (racer.global_position - npc.global_position).slide(Vector3.UP)
		var dist := to.length()
		if dist < 0.5 or dist > best_dist or forward.dot(to / dist) < follow_detect_angle:
			continue
		if (racer.velocity as Vector3).dot(forward) < -1.0:
			continue
		var off_path: Vector3 = (racer.global_position - from.point_ahead(dist)).slide(Vector3.UP)
		if off_path.length() > TrafficNetworkBaker.VEHICLE_WIDTH:
			continue
		best = racer
		best_dist = dist
	return best


## Fastest `rider` can go and still stop a queue's spacing (EXIT_CLEARANCE) behind a racer `dist`
## ahead, centre to centre. stop_line_speed already leaves our half length.
static func _follow_speed(rider: NPCRiderEntity, dist: float) -> float:
	return rider.stop_line_speed(dist - EXIT_CLEARANCE + NPCRiderEntity.STOP_LINE_BUFFER)


## Blocked: moves to a neighbour lane taking the same turn at the next junction, if its nearest
## rider ahead is further off than ours and it's clear to merge. Throttled like lane_speed.
func _change_lane_around(blocker: Node3D) -> void:
	var now := Time.get_ticks_msec()
	# Claimed means we're at or in the junction; mid-change, don't weave straight back
	if _claimed >= 0 or !is_zero_approx(_lane_shift) or now < _next_lane_check_ms:
		return
	_next_lane_check_ms = now + npc.next_scan_delay_ms()
	var network := follower.network
	var turn := network.lanes[follower.next_turn_lane()]
	var blocked_at := npc.global_position.distance_to(blocker.global_position)
	for lane in network.lanes[follower.lane].neighbors:
		var next := network.lanes[lane].successors.filter(
			func(s: int) -> bool:
				return network.lanes[s].junction == turn.junction and network.lanes[s].turn_dir == turn.turn_dir
		)
		if next.is_empty():
			continue
		var curve := network.lane_curve(lane)
		var offset := curve.get_closest_offset(npc.global_position)
		# Off either end: that lane doesn't run beside us here
		if offset <= 0.0 or offset >= curve.get_baked_length():
			continue
		var there := TrafficLaneFollower.new(network, lane, offset)
		there.latch(next[0])
		var ahead := _rider_ahead(there)
		if ahead != null and npc.global_position.distance_to(ahead.global_position) <= blocked_at:
			continue
		if !_clear_to_merge(there):
			continue
		follower = there
		# Starts where we are and eases onto the new lane as we drive
		var lane_transform := there.get_transform()
		_lane_shift = (npc.global_position - lane_transform.origin).dot(lane_transform.basis.x) - npc.line_offset
		return


## No racer beside us on `there`'s lane, and every rider behind us on it can still stop short.
func _clear_to_merge(there: TrafficLaneFollower) -> bool:
	var pos := there.point_ahead(0.0)
	for racer in other_racers:
		# Despawned since the last LOD pass — skip is intentional
		if !is_instance_valid(racer):
			continue
		# Two half lengths
		if racer.global_position.distance_to(pos) < 2.0 * NPCRiderEntity.STOP_LINE_BUFFER:
			return false
	for other: NPCTrafficState in lane_riders[there.lane]:
		var gap := there.offset - other.follower.offset
		# Recovered onto another lane and not ticked since — skip is intentional
		if other.follower.lane != there.lane or gap < 0.0:
			continue
		if _follow_speed(other.npc, gap) <= other.npc.current_speed:
			return false
	return true


## Moves us between lane_riders' lists as the follower changes lane; -1 drops us from all.
func _track_lane(lane: int) -> void:
	if lane == _lane:
		return
	if _lane >= 0:
		lane_riders[_lane].erase(self)
	_lane = lane
	if _lane >= 0:
		lane_riders[_lane].append(self)


## Caps target_speed at the next stop line until that junction lets us in.
func _gate(target_speed: float, delta: float) -> float:
	# Still inside the junction we claimed, or already let into the next
	if _claimed >= 0:
		return target_speed
	var line_speed := npc.stop_line_speed(follower.dist_to_junction())
	# Only ask once the line actually slows us, so riders far off or queued behind don't claim
	if line_speed >= target_speed:
		# Queued behind a rider we hadn't seen when we arrived: an arrival that isn't at the line
		# holds every conflicting turn and deadlocks the junction
		_leave_junction()
		return target_speed
	var turn := follower.next_turn_lane()
	var network := follower.network
	var junction := junctions[network.lanes[turn].junction]
	# A red holds however long we've waited (bar right on red); the timeout is for deadlocks the gate can't see
	var lit := network.control(turn) == TrafficIntersection.ControlType.LIGHT
	if lit and network.light(turn, NetworkTime.time) != TrafficJunctionData.Light.GREEN:
		# Out of line while held, or we'd hold up the cross street's green
		_leave_junction()
		if !_right_on_red(turn, junction):
			return line_speed
	else:
		_wait_time += delta
		_queued = junction
		junction.arrive(npc, turn)
		# A conflicting rider inside or ahead in line holds too: forcing past one is how the box gridlocks
		if !junction.may_enter(npc, turn):
			return line_speed
		var let_in := _stop_sign_lets_in(turn) and _exit_clear(turn)
		if _wait_time < junction_timeout and !let_in:
			return line_speed
	# Claimed on grant, not on crossing the line, so two riders can't both see it empty
	junction.enter(npc, turn)
	_queued = null
	_claimed = turn
	_wait_time = 0.0
	return target_speed


## STOP: a full stop at the line. Turn order is may_enter's, so turns that don't cross go together.
func _stop_sign_lets_in(turn: int) -> bool:
	if follower.network.control(turn) != TrafficIntersection.ControlType.STOP:
		return true
	return _stopped_time >= full_stop_time


## A red lets a right turn in after a full stop, if nothing conflicting is inside or waiting. Never
## queued, so may_enter checks every arrival and it yields to the green instead of holding it up.
func _right_on_red(turn: int, junction: JunctionState) -> bool:
	return (
		follower.network.lanes[turn].turn_dir == TrafficLaneData.TurnDir.RIGHT
		and _stopped_time >= full_stop_time
		and junction.may_enter(npc, turn)
		and _exit_clear(turn)
	)


func _leave_junction() -> void:
	# A wreck mustn't hold its place in an arrival queue either
	if _queued:
		_queued.leave(npc)
		_queued = null
	if _claimed < 0:
		return
	junctions[follower.network.lanes[_claimed].junction].leave(npc)
	_claimed = -1


## No stopped rider sitting in the start of our exit lane, so we won't end up parked in the box.
func _exit_clear(turn: int) -> bool:
	var points := follower.network.lanes[turn].points
	var exit_start := points[-1]
	var exit_dir := (points[-1] - points[-2]).slide(Vector3.UP).normalized()
	for racer in npc.get_tree().get_nodes_in_group(UtilsConstants.GROUPS["Racers"]):
		if racer == npc or npc.horizontal_speed(racer) > 1.0:
			continue
		var to: Vector3 = (racer.global_position - exit_start).slide(Vector3.UP)
		var along := to.dot(exit_dir)
		var in_lane := (to - exit_dir * along).length() < TrafficNetworkBaker.VEHICLE_WIDTH
		if in_lane and along > -NPCRiderEntity.STOP_LINE_BUFFER and along < EXIT_CLEARANCE:
			return false
	return true


## ContactArea touched a racer's body, or another traffic rider's ContactArea. Both sides of a
## hit see it, so each rider only crashes itself; the manager takes a player victim down too.
func _on_contact(other: Node3D) -> void:
	# A wreck is inert — otherwise a rider respawned at the crash site re-crashes on it
	if npc.npc_state == NPCRiderEntity.NPCState.CRASHED:
		return
	var racer: Node3D = other.get_parent() if other is Area3D else other
	# The crash_collision mask also catches level obstacles
	if !racer.is_in_group(UtilsConstants.GROUPS["Racers"]):
		return
	# A player has no body to bump off, so any touch crashes them
	if racer is not PlayerEntity and (npc.velocity - racer.velocity).length() < contact_min_speed_delta:
		return
	crashed.emit(racer)


func _on_near_miss_entered(body: Node3D) -> void:
	# The crash_collision mask also catches level obstacles
	if body is PlayerEntity:
		_passing[body] = body.crash_count


func _on_near_miss_exited(body: Node3D) -> void:
	# Untracked: an obstacle, or a player already inside when this state cleared _passing
	if !_passing.has(body):
		return
	var clean: bool = _passing[body] == body.crash_count and !body.is_crashed
	_passing.erase(body)
	# A crash since entering (into us or anything else) or a despawn mid-pass isn't a near miss
	if clean and !body.is_queued_for_deletion():
		near_missed.emit(body)


func _get_configuration_warnings() -> PackedStringArray:
	var issues := PackedStringArray()
	if npc == null:
		issues.append("npc must not be empty")
	return issues
