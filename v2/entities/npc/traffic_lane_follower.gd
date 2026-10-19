class_name TrafficLaneFollower extends RefCounted

## A traffic rider's place on a baked TrafficNetworkData: current lane + distance along it. Forks
## pick a random successor, latched until the rider leaves that lane.

# Within this of a lane's end counts as having left it
const END_MARGIN := 0.5

var network: TrafficNetworkData
var lane: int
var offset: float
# Lane index -> successor picked for it
var _choices := {}


func _init(network_data: TrafficNetworkData, start_lane: int, start_offset: float):
	network = network_data
	lane = start_lane
	offset = start_offset


## Re-reads offset off the rider's position, moving onto the next lane once past the end.
func update(pos: Vector3):
	offset = network.lane_curve(lane).get_closest_offset(pos)
	while offset >= network.lane_curve(lane).get_baked_length() - END_MARGIN:
		_leave_lane()
		offset = network.lane_curve(lane).get_closest_offset(pos)


func point_ahead(dist: float) -> Vector3:
	var at_lane := lane
	var at_offset := offset + dist
	while at_offset > network.lane_curve(at_lane).get_baked_length():
		at_offset -= network.lane_curve(at_lane).get_baked_length()
		at_lane = _next_lane(at_lane)
	return network.lane_curve(at_lane).sample_baked(at_offset)


## Moves the follower itself along the lanes, e.g. to drop a recovered rider further on.
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
