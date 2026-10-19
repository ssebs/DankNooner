@tool
class_name TrafficNetworkBaker extends RefCounted

## Builds TrafficNetworkData from a TrafficNetwork's authoring nodes, for both the Bake button and
## the editor's live preview. Lane index 0 is the innermost lane of a direction.

const SAMPLE_SPACING := 2.0
# Corners are rounded by a curve starting this far before each interior point
const CORNER_CUT := 12.0
# Turn lanes passing closer than this conflict
const VEHICLE_WIDTH := 2.0
const CLIP_STEPS := 12
# Slots run clockwise seen from above (N, E, S, W), so (exit - entry) % 4 gives the turn
const TURN_BY_SLOT_DELTA: Array[TrafficLaneData.TurnDir] = [
	TrafficLaneData.TurnDir.U_TURN,
	TrafficLaneData.TurnDir.LEFT,
	TrafficLaneData.TurnDir.THROUGH,
	TrafficLaneData.TurnDir.RIGHT,
]

var data := TrafficNetworkData.new()
# Points with no road surface below; baked at their own height
var missed_points: Array[TrafficRoadPoint] = []

var _network: TrafficNetwork
var _intersections: Array[TrafficIntersection]
# Vector2i(junction, slot) -> lane indices at that slot, innermost first
var _incoming := {}
var _outgoing := {}
# Turn lane index -> the road lane it starts from
var _turn_entry := {}


func _init(network: TrafficNetwork):
	_network = network
	_intersections = network.get_intersections()


static func source_hash(network: TrafficNetwork) -> int:
	var parts := []
	for road in network.get_roads():
		parts.append([road.name, road.lane_width])
		for point in road.get_points():
			parts.append([point.global_position, point.lane_count])
	for intersection in network.get_intersections():
		parts.append([intersection.global_transform, intersection.radius, intersection.control])
		parts.append([intersection.green_duration, intersection.amber_duration])
		for slot in TrafficIntersection.Slot.values():
			var road := intersection.get_slot_road(slot)
			parts.append(road.name if road else &"")
	return parts.hash()


func build(with_conflicts: bool) -> TrafficNetworkData:
	for intersection in _intersections:
		var junction := TrafficJunctionData.new()
		junction.position = intersection.global_position
		junction.control = intersection.control
		junction.green_duration = intersection.green_duration
		junction.amber_duration = intersection.amber_duration
		data.junctions.append(junction)
	for road in _network.get_roads():
		_build_road(road)
	for i in _intersections.size():
		_build_turns(i)
		if with_conflicts:
			_mark_conflicts(i)
	data.source_hash = source_hash(_network)
	return data


func _build_road(road: TrafficRoad):
	var points := road.get_points()
	# Invalid roads are reported by config warnings; the preview just skips them
	if points.size() < 2 or points[0].resolved_lane_count() < 2:
		return
	var positions := PackedVector3Array()
	var counts := PackedInt32Array()
	for point in points:
		var hit := point.road_hit()
		if hit.is_empty():
			missed_points.append(point)
		positions.append(point.global_position if hit.is_empty() else hit.position)
		counts.append(int(point.resolved_lane_count() / 2.0))
	var start := _attachment(road, points[0])
	var end := _attachment(road, points[-1])
	_build_direction(road.lane_width, positions, counts, start, end)
	positions.reverse()
	counts.reverse()
	_build_direction(road.lane_width, positions, counts, end, start)


# Vector2i(junction, slot), or (-1, -1) for an unlinked end (a config warning)
func _attachment(road: TrafficRoad, end: TrafficRoadPoint) -> Vector2i:
	for i in _intersections.size():
		for slot in TrafficIntersection.Slot.values():
			if _intersections[i].get_slot_road(slot) == road and _intersections[i].slot_end(slot) == end:
				return Vector2i(i, slot)
	return Vector2i(-1, -1)


# Lanes travelling positions[0] -> positions[-1] on the right. Built as one piece per lane per
# segment, then joined back into whole lanes wherever nothing merges or splits.
func _build_direction(
	lane_width: float, positions: PackedVector3Array, counts: PackedInt32Array, start: Vector2i, end: Vector2i
):
	var samples := PackedVector3Array()
	var markers := _round_corners(positions, samples)
	var rights := _right_vectors(samples)
	var last_seg := positions.size() - 2
	var pieces: Array[TrafficLaneData] = []
	var grid := {}  # Vector2i(lane, segment) -> piece index
	for k in last_seg + 1:
		for j in maxi(counts[k], counts[k + 1]):
			# A lane missing at one end sits on the outermost remaining lane there, so it tapers
			var from_offset := (mini(j, counts[k] - 1) + 0.5) * lane_width
			var to_offset := (mini(j, counts[k + 1] - 1) + 0.5) * lane_width
			var lane := TrafficLaneData.new()
			lane.points = _offset_slice(samples, rights, markers[k], markers[k + 1], from_offset, to_offset)
			if k == 0 and start.x >= 0:
				lane.points = _clip_start(lane.points, _intersections[start.x])
			if k == last_seg and end.x >= 0:
				lane.points = _clip_end(lane.points, _intersections[end.x])
			grid[Vector2i(j, k)] = pieces.size()
			pieces.append(lane)

	for k in last_seg:
		for j in maxi(counts[k], counts[k + 1]):
			var lane := pieces[grid[Vector2i(j, k)]]
			if j >= counts[k + 1]:
				# Merged out over this segment: continues as the lane it tapered into
				lane.successors.append(grid[Vector2i(counts[k + 1] - 1, k + 1)])
				continue
			lane.successors.append(grid[Vector2i(j, k + 1)])
			if j == counts[k + 1] - 1:
				# The outermost lane feeds any lanes splitting off it on the next segment
				for split in range(counts[k + 1], counts[k + 2]):
					lane.successors.append(grid[Vector2i(split, k + 1)])

	var lane_index := _join_pieces(pieces)
	if start.x >= 0:
		_outgoing[start] = range(counts[0]).map(func(j): return lane_index[grid[Vector2i(j, 0)]])
	if end.x >= 0:
		_incoming[end] = range(counts[-1]).map(func(j): return lane_index[grid[Vector2i(j, last_seg)]])


# Fills samples along the point chain with each interior corner rounded. Returns the sample index
# of each point (the corner curve's midpoint for interior points).
func _round_corners(positions: PackedVector3Array, samples: PackedVector3Array) -> PackedInt32Array:
	var markers := PackedInt32Array([0])
	samples.append(positions[0])
	for k in range(1, positions.size() - 1):
		var corner := positions[k]
		var shortest := minf(corner.distance_to(positions[k - 1]), corner.distance_to(positions[k + 1]))
		var cut := minf(CORNER_CUT, shortest / 2.0)
		var enter := corner + (positions[k - 1] - corner).normalized() * cut
		var leave := corner + (positions[k + 1] - corner).normalized() * cut
		_append_line(samples, enter)
		# Even, so the midpoint lands on a sample
		var steps := maxi(2, ceili(cut / SAMPLE_SPACING) * 2)
		for s in range(1, steps + 1):
			var t := float(s) / steps
			samples.append(enter.lerp(corner, t).lerp(corner.lerp(leave, t), t))
			if s * 2 == steps:
				markers.append(samples.size() - 1)
	_append_line(samples, positions[-1])
	markers.append(samples.size() - 1)
	return markers


func _append_line(samples: PackedVector3Array, to: Vector3):
	var from := samples[-1]
	var steps := maxi(1, ceili(from.distance_to(to) / SAMPLE_SPACING))
	for s in range(1, steps + 1):
		samples.append(from.lerp(to, float(s) / steps))


func _right_vectors(samples: PackedVector3Array) -> PackedVector3Array:
	var rights := PackedVector3Array()
	for i in samples.size():
		var tangent := samples[mini(i + 1, samples.size() - 1)] - samples[maxi(i - 1, 0)]
		rights.append(tangent.slide(Vector3.UP).normalized().cross(Vector3.UP))
	return rights


# samples[from..to] pushed right, easing from from_offset to to_offset over the segment
func _offset_slice(
	samples: PackedVector3Array, rights: PackedVector3Array, from: int, to: int, from_offset: float, to_offset: float
) -> PackedVector3Array:
	var length := 0.0
	for i in range(from, to):
		length += samples[i].distance_to(samples[i + 1])
	var out := PackedVector3Array()
	var travelled := 0.0
	for i in range(from, to + 1):
		if i > from:
			travelled += samples[i - 1].distance_to(samples[i])
		var t := travelled / length if length > 0.0 else 0.0
		out.append(samples[i] + rights[i] * lerpf(from_offset, to_offset, smoothstep(0.0, 1.0, t)))
	return out


# Drops the start of a lane that's inside the intersection's box, cutting it at the box edge
func _clip_start(points: PackedVector3Array, intersection: TrafficIntersection) -> PackedVector3Array:
	if not intersection.is_inside_box(points[0]):
		return points
	for i in range(1, points.size()):
		if intersection.is_inside_box(points[i]):
			continue
		var inside := points[i - 1]
		var outside := points[i]
		for step in CLIP_STEPS:
			var mid := inside.lerp(outside, 0.5)
			if intersection.is_inside_box(mid):
				inside = mid
			else:
				outside = mid
		var clipped := PackedVector3Array([outside])
		clipped.append_array(points.slice(i))
		return clipped
	# Whole piece inside the box; Bake rejects it, the preview skips it
	return PackedVector3Array()


func _clip_end(points: PackedVector3Array, intersection: TrafficIntersection) -> PackedVector3Array:
	var reversed := points.duplicate()
	reversed.reverse()
	var clipped := _clip_start(reversed, intersection)
	clipped.reverse()
	return clipped


# Appends pieces to data.lanes, joining each piece with a single successor that has no other
# predecessor. Returns each piece's index in data.lanes.
func _join_pieces(pieces: Array[TrafficLaneData]) -> PackedInt32Array:
	var pred_count := PackedInt32Array()
	pred_count.resize(pieces.size())
	var pred := PackedInt32Array()
	pred.resize(pieces.size())
	for i in pieces.size():
		for s in pieces[i].successors:
			pred_count[s] += 1
			pred[s] = i
	# Up front: joining rewrites successors
	var is_continuation: Array[bool] = []
	for i in pieces.size():
		is_continuation.append(pred_count[i] == 1 and pieces[pred[i]].successors.size() == 1)

	var lane_index := PackedInt32Array()
	lane_index.resize(pieces.size())
	var first_new := data.lanes.size()
	for i in pieces.size():
		if is_continuation[i]:
			continue
		var head := pieces[i]
		lane_index[i] = data.lanes.size()
		var cur := i
		while pieces[cur].successors.size() == 1 and is_continuation[pieces[cur].successors[0]]:
			cur = pieces[cur].successors[0]
			lane_index[cur] = lane_index[i]
			head.points.append_array(pieces[cur].points.slice(1))
		head.successors = pieces[cur].successors
		data.lanes.append(head)

	for i in range(first_new, data.lanes.size()):
		var successors: Array[int] = []
		for s in data.lanes[i].successors:
			successors.append(lane_index[s])
		data.lanes[i].successors = successors
	return lane_index


func _build_turns(junction: int):
	var slots := TrafficIntersection.Slot.values().filter(func(s): return _incoming.has(Vector2i(junction, s)))
	for entry in slots:
		# A cul-de-sac (one linked slot) only turns back; otherwise no U-turns
		var exits := slots if slots.size() == 1 else slots.filter(func(s): return s != entry)
		for exit in exits:
			var turn_dir := TURN_BY_SLOT_DELTA[(exit - entry + 4) % 4]
			var from: Array = _incoming[Vector2i(junction, entry)]
			var to: Array = _outgoing[Vector2i(junction, exit)]
			# The only way out takes every lane, whatever the turn
			var pairing := TrafficLaneData.TurnDir.THROUGH if exits.size() == 1 else turn_dir
			for pair in _turn_pairs(pairing, from.size(), to.size()):
				_add_turn(junction, entry, turn_dir, from[pair.x], to[pair.y])


# Vector2i(from lane, to lane): left from the innermost, right from the outermost, through/U-turn
# lane-for-lane (clamped when counts differ)
func _turn_pairs(turn_dir: TrafficLaneData.TurnDir, from_count: int, to_count: int) -> Array[Vector2i]:
	match turn_dir:
		TrafficLaneData.TurnDir.LEFT:
			return [Vector2i(0, 0)]
		TrafficLaneData.TurnDir.RIGHT:
			return [Vector2i(from_count - 1, to_count - 1)]
	var pairs: Array[Vector2i] = []
	for i in from_count:
		pairs.append(Vector2i(i, mini(i, to_count - 1)))
	return pairs


func _add_turn(junction: int, entry: int, turn_dir: TrafficLaneData.TurnDir, from_lane: int, to_lane: int):
	var from := data.lanes[from_lane].points
	var to := data.lanes[to_lane].points
	# Clipped away entirely; Bake rejects it, the preview skips it
	if from.size() < 2 or to.size() < 2:
		return
	var start := from[-1]
	var end := to[0]
	var reach := start.distance_to(end) * 0.4
	if turn_dir == TrafficLaneData.TurnDir.U_TURN:
		reach = _intersections[junction].radius
	var control_in := start + (from[-1] - from[-2]).normalized() * reach
	var control_out := end - (to[1] - to[0]).normalized() * reach
	var steps := maxi(4, ceili((start.distance_to(end) + reach) / SAMPLE_SPACING))

	var turn := TrafficLaneData.new()
	for s in steps + 1:
		turn.points.append(start.bezier_interpolate(control_in, control_out, end, float(s) / steps))
	turn.successors.append(to_lane)
	turn.junction = junction
	turn.entry_slot = entry
	turn.turn_dir = turn_dir
	_turn_entry[data.lanes.size()] = from_lane
	data.lanes[from_lane].successors.append(data.lanes.size())
	data.lanes.append(turn)


func _mark_conflicts(junction: int):
	var turns: Array[int] = []
	for i in data.lanes.size():
		if data.lanes[i].junction == junction:
			turns.append(i)
	for a in turns.size():
		for b in range(a + 1, turns.size()):
			var lane_a := turns[a]
			var lane_b := turns[b]
			# Same entry lane = same queue, already ordered
			if _turn_entry[lane_a] == _turn_entry[lane_b]:
				continue
			if _paths_close(data.lanes[lane_a].points, data.lanes[lane_b].points):
				data.lanes[lane_a].conflicts.append(lane_b)
				data.lanes[lane_b].conflicts.append(lane_a)


func _paths_close(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	for i in a.size() - 1:
		for j in b.size() - 1:
			var closest := Geometry2D.get_closest_points_between_segments(
				_flat(a[i]), _flat(a[i + 1]), _flat(b[j]), _flat(b[j + 1])
			)
			if closest[0].distance_to(closest[1]) < VEHICLE_WIDTH:
				return true
	return false


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
