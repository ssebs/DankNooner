@tool
## Free-roam traffic behavior: circulate the level's baked TrafficNetwork forever.
## Rides its lane on rails via a TrafficLaneFollower (random turn at each fork) with no
## physics, so speed is all it decides. Tucks in behind whatever is ahead, waits its
## turn at junctions, and reports crashes to NPCTrafficManager, which owns the recovery.
class_name NPCTrafficState extends State

## Hit another racer — the manager wipes the rider out, respawns it, and takes
## the racer we hit down with us if it's a player.
signal crashed(victim: Node3D)

@export var npc: NPCRiderEntity
## A racer within this range and forward cone that's slower than us gets
## followed rather than passed (traffic doesn't overtake in v1).
## Must cover braking distance from cruise + the gap + one scan interval of travel.
@export var follow_detect_range: float = 20.0
@export var follow_detect_angle: float = 0.7
## Relative speed (m/s) that makes rider-to-rider contact an actual impact — riders
## queueing nose-to-tail brush at matched speed and shouldn't both wipe out for it.
@export var contact_min_speed_delta: float = 6.0
## Waited this long at a stop line, go anyway. Breaks deadlocks the gate can't see.
@export var junction_timeout: float = 8.0

## A stopped rider this far into our exit lane leaves no room past the box: our half
## length, the queue gap, its half length.
const EXIT_CLEARANCE := 3.0 * NPCRiderEntity.STOP_LINE_BUFFER

## Set by NPCTrafficManager on spawn and on every recovery.
var follower: TrafficLaneFollower
## Set by NPCTrafficManager on spawn, indexed like TrafficNetworkData.junctions.
var junctions: Array[JunctionState]

# Turn lane we've been let onto, -1 when none
var _claimed := -1
# Stop-sign junction whose arrival queue we're in
var _queued: JunctionState
var _wait_time := 0.0


func Enter(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
	npc.contact_area.body_entered.connect(_on_contact)
	npc.contact_area.area_entered.connect(_on_contact)


func Exit(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
	npc.contact_area.body_entered.disconnect(_on_contact)
	npc.contact_area.area_entered.disconnect(_on_contact)
	set_contact(false)
	_leave_junction()


## NPCTrafficManager's LOD turns contact on only while a player is near.
func set_contact(on: bool) -> void:
	npc.contact_area.set_deferred("monitoring", on)
	npc.contact_area.set_deferred("monitorable", on)


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
	# Close in on the rider ahead only as fast as we can still stop a buffer behind it.
	# The second buffer is its half length.
	var blocker := npc.nearest_racer_ahead(follow_detect_range, follow_detect_angle, false)
	if blocker != null:
		var gap := npc.global_position.distance_to(blocker.global_position) - NPCRiderEntity.STOP_LINE_BUFFER
		target_speed = minf(target_speed, npc.horizontal_speed(blocker) + npc.stop_line_speed(gap))
	target_speed = _gate(target_speed, delta)
	npc.ramp_speed(target_speed, delta)
	follower.advance(npc.current_speed * delta)
	var lane_transform := follower.get_transform()
	npc.ride_to(lane_transform.origin + lane_transform.basis.x * npc.line_offset, -lane_transform.basis.z, delta)


## Caps target_speed at the next stop line until that junction lets us in.
func _gate(target_speed: float, delta: float) -> float:
	# Still inside the junction we claimed, or already let into the next
	if _claimed >= 0:
		return target_speed
	var line_speed := npc.stop_line_speed(follower.dist_to_junction())
	# Only ask once the line actually slows us, so riders far off or queued behind don't claim
	if line_speed >= target_speed:
		return target_speed
	var turn := follower.next_turn_lane()
	var network := follower.network
	var junction := junctions[network.lanes[turn].junction]
	# A red holds however long we've waited; the timeout is for deadlocks the gate can't see
	var lit := network.control(turn) == TrafficIntersection.ControlType.LIGHT
	if lit and network.light(turn, NetworkTime.time) != TrafficJunctionData.Light.GREEN:
		return line_speed
	_wait_time += delta
	var let_in := _stop_sign_lets_in(junction, turn) and junction.may_enter(turn) and _exit_clear(turn)
	if _wait_time < junction_timeout and !let_in:
		return line_speed
	# Claimed on grant, not on crossing the line, so two riders can't both see it empty
	junction.enter(npc, turn)
	_queued = null
	_claimed = turn
	_wait_time = 0.0
	return target_speed


## STOP: a full stop at the line, then first come first served.
func _stop_sign_lets_in(junction: JunctionState, turn: int) -> bool:
	if follower.network.control(turn) != TrafficIntersection.ControlType.STOP:
		return true
	if !is_zero_approx(npc.current_speed):
		return false
	_queued = junction
	return junction.arrive(npc)


func _leave_junction() -> void:
	# A wreck mustn't hold its place in a stop-sign queue either
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
	var racer: Node3D = other.get_parent() if other is Area3D else other
	# The crash_collision mask also catches level obstacles
	if !racer.is_in_group(UtilsConstants.GROUPS["Racers"]):
		return
	# A player has no body to bump off, so any touch crashes them, wrecks included
	if racer is not PlayerEntity and (npc.velocity - racer.velocity).length() < contact_min_speed_delta:
		return
	crashed.emit(racer)


func _get_configuration_warnings() -> PackedStringArray:
	var issues := PackedStringArray()
	if npc == null:
		issues.append("npc must not be empty")
	return issues
