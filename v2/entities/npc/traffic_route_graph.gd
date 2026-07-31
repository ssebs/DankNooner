## Lane-successor table for traffic riders, built from the RoadManager's AI lane
## group and rebuilt whenever the road generator regenerates its lanes.
##
## Why this exists: RoadLaneAgent only follows a lane's single `lane_next`
## NodePath, and RoadContainer only ever links segment-to-segment — the lanes
## the intersection generator emits (one through lane plus a turn lane per
## branch) get their tags but never a `lane_next`. So the addon can't route
## through a junction at all. We rebuild the missing links geometrically: any
## lane whose START sits within `snap_distance` of this lane's END, facing
## roughly the same way, is a candidate successor.
##
## Lanes are freed and regenerated wholesale by RoadContainer.rebuild_segments
## (which it defers on _ready), so every cached RoadLane here is potentially a
## freed instance — hence rebuild() and the validity checks below.
class_name TrafficRouteGraph extends RefCounted

var lanes: Array[RoadLane] = []

var _successors: Dictionary[RoadLane, Array] = {}
var _snap_distance: float
var _heading_tolerance: float


func _init(road_lanes: Array, snap_distance: float = 6.0, heading_tolerance: float = 0.3) -> void:
	_snap_distance = snap_distance
	_heading_tolerance = heading_tolerance
	rebuild(road_lanes)


## Re-derive the whole table. Done in place so riders holding this graph keep
## working across a road rebuild.
func rebuild(road_lanes: Array) -> void:
	lanes.clear()
	_successors.clear()
	for lane in road_lanes:
		# Containers can each carry their own lane group, so the same lane can
		# show up twice in the gathered list.
		if lane is RoadLane and !lanes.has(lane):
			lanes.append(lane)
	for lane in lanes:
		_successors[lane] = _find_successors(lane)


## Lanes a rider may continue onto from `lane`. Empty where the road just ends —
## and where `lane` was generated after this graph was last rebuilt, since the
## caller's recovery (re-latch to the nearest lane) is the right answer there too.
func next_lanes(lane: RoadLane) -> Array:
	return _successors.get(lane, [])


## A lane that is still alive. Stale entries are pruned as we hit them.
func random_lane() -> RoadLane:
	while !lanes.is_empty():
		var lane: RoadLane = lanes.pick_random()
		if is_instance_valid(lane):
			return lane
		lanes.erase(lane)
	return null


## Where a rider dropped somewhere ALONG this lane should sit — `t` is 0..1 of the way
## down the curve. Spawning everyone at t=0 stacks them: the junction generator emits a
## through lane plus a turn lane per branch that all START within a few metres of each
## other (the same proximity _find_successors links on), so lane starts cluster hard at
## intersections while the road between them sits empty.
func lane_transform_at(lane: RoadLane, t: float) -> Transform3D:
	var length := lane.curve.get_baked_length()
	var offset := clampf(t, 0.0, 1.0) * length
	var pos := lane.to_global(lane.curve.sample_baked(offset))
	var ahead := lane.to_global(lane.curve.sample_baked(minf(offset + 1.0, length)))
	var dir := ahead - pos
	# Landed on the last baked point, so there's nothing ahead to aim at.
	if dir.length_squared() < 0.001:
		dir = _heading_at_end(lane)
	return Transform3D(Basis.looking_at(dir), pos)


func _find_successors(lane: RoadLane) -> Array:
	var linked := lane.get_node_or_null(lane.lane_next) as RoadLane
	if linked != null:
		return [linked]

	var out: Array = []
	var lane_end := lane.get_lane_end()
	var heading := _heading_at_end(lane)
	for other in lanes:
		if other == lane:
			continue
		if other.get_lane_start().distance_to(lane_end) > _snap_distance:
			continue
		if heading.dot(_heading_at_start(other)) < _heading_tolerance:
			continue
		out.append(other)
	return out


## Travel direction of the lane curve at its first point.
func _heading_at_start(lane: RoadLane) -> Vector3:
	var sample_dist := minf(1.0, lane.curve.get_baked_length())
	var ahead := lane.to_global(lane.curve.sample_baked(sample_dist))
	return (ahead - lane.get_lane_start()).normalized()


## Travel direction of the lane curve at its last point.
func _heading_at_end(lane: RoadLane) -> Vector3:
	var length := lane.curve.get_baked_length()
	var behind := lane.to_global(lane.curve.sample_baked(maxf(0.0, length - 1.0)))
	return (lane.get_lane_end() - behind).normalized()
