class_name TrafficLaneFollower extends RefCounted

## A traffic rider's place on a baked TrafficNetworkData: current lane + distance along it. Forks
## pick a random successor, latched until the rider leaves that lane.

var network: TrafficNetworkData
var lane: int
var offset: float
# Lane index -> successor picked for it
var _choices := {}


func _init(network_data: TrafficNetworkData, start_lane: int, start_offset: float):
	network = network_data
	lane = start_lane
	offset = start_offset


func point_ahead(dist: float) -> Vector3:
	var at_lane := lane
	var at_offset := offset + dist
	while at_offset > network.lane_curve(at_lane).get_baked_length():
		at_offset -= network.lane_curve(at_lane).get_baked_length()
		at_lane = _next_lane(at_lane)
	return network.lane_curve(at_lane).sample_baked(at_offset)


## The next turn lane on the latched path, past the one we're on if we're in a junction.
func next_turn_lane() -> int:
	var at := _next_lane(lane)
	while network.lanes[at].junction < 0:
		at = _next_lane(at)
	return at


## Distance along the latched path to the next junction's stop line (a turn lane's first point).
func dist_to_junction() -> float:
	var dist := network.lane_curve(lane).get_baked_length() - offset
	var at := _next_lane(lane)
	while network.lanes[at].junction < 0:
		dist += network.lane_curve(at).get_baked_length()
		at = _next_lane(at)
	return dist


## Each lane on the latched path starting within max_dist, mapped to how far ahead it starts
## (negative for the one we're on).
func lanes_ahead(max_dist: float) -> Dictionary[int, float]:
	var starts: Dictionary[int, float] = {}
	var at := lane
	var start := -offset
	while start < max_dist:
		starts[at] = start
		start += network.lane_curve(at).get_baked_length()
		at = _next_lane(at)
	return starts


## Moves along the lanes. The rider rides wherever this puts it.
func advance(dist: float):
	offset += dist
	while offset > network.lane_curve(lane).get_baked_length():
		offset -= network.lane_curve(lane).get_baked_length()
		_leave_lane()


## Facing along the lane, front = -Z like the rider.
func get_transform() -> Transform3D:
	var pos := point_ahead(0.0)
	var dir := (point_ahead(1.0) - pos).slide(Vector3.UP)
	return Transform3D(Basis.looking_at(dir), pos)


func _leave_lane():
	var next := _next_lane(lane)
	_choices.erase(lane)
	lane = next


func _next_lane(from: int) -> int:
	if not _choices.has(from):
		_choices[from] = network.lanes[from].successors.pick_random()
	return _choices[from]
