## The racing line race bots ride, baked once per race on the server from the level's road
## navmesh: road-only navmesh paths chained through the checkpoints, smoothed toward corner
## insides, then fit with a Curve3D. Every sample keeps its curvature, the corner speed that
## implies, and the road room either side. Offsets `s` are metres along the line.
##
## Braking is per bot, not baked here: each bot runs braking_profile with its own deceleration,
## so bots brake from their own numbers and never from one shared knob.
class_name NPCRacingLine extends RefCounted

## Road-room probe step: the navmesh's cell size, finer than the samples so widths aren't coarse.
const ROOM_STEP: float = 0.5
## Below this curvature (1/m) a sample counts as straight, which caps corner speed.
const MIN_CURVATURE: float = 0.0001

var closed: bool
var sample_spacing: float

var _curve := Curve3D.new()
## Indexed by sample, sample i sits at offset i * sample_spacing.
var _curvature := PackedFloat32Array()
var _corner_speed := PackedFloat32Array()
var _room_left := PackedFloat32Array()
var _room_right := PackedFloat32Array()


func _init(
	road_region: RID,
	checkpoints: PackedVector3Array,
	is_closed: bool,
	spacing: float,
	smoothing_passes: int,
	corner_grip: float,
	max_half_width: float
) -> void:
	closed = is_closed
	sample_spacing = spacing
	var points := _resample(_corridor(road_region, checkpoints))
	for i in smoothing_passes:
		points = _smooth(points, road_region)
	_fit_curve(points)
	_bake_samples(road_region, corner_grip, max_half_width)


func get_length() -> float:
	return _curve.get_baked_length()


func wrap_offset(s: float) -> float:
	return fposmod(s, get_length()) if closed else clampf(s, 0.0, get_length())


func point_at(s: float) -> Vector3:
	return _curve.sample_baked(wrap_offset(s), true)


## Horizontal unit vector right of travel.
func right_at(s: float) -> Vector3:
	var forward := point_at(s + 1.0) - point_at(s - 1.0)
	forward.y = 0.0
	return forward.normalized().cross(Vector3.UP)


## Signed, positive = turning left.
func curvature_at(s: float) -> float:
	return _curvature[_index(s)]


## Road room from the line to the eroded road edge, on the right for side > 0, else the left.
func half_width_at(s: float, side: float) -> float:
	return (_room_right if side > 0.0 else _room_left)[_index(s)]


## Target speed per sample: corner speed scaled by corner_scale, then a backward pass so a bot
## decelerating at decel reaches each corner at its speed — braking starts before the corner.
func braking_profile(decel: float, corner_scale: float) -> PackedFloat32Array:
	var n := _corner_speed.size()
	var profile := PackedFloat32Array()
	profile.resize(n)
	for i in n:
		profile[i] = _corner_speed[i] * corner_scale
	var brake_gain := 2.0 * decel * sample_spacing
	if !closed:
		for i in range(n - 2, -1, -1):
			profile[i] = minf(profile[i], sqrt(profile[i + 1] * profile[i + 1] + brake_gain))
		return profile
	# Twice round, so a corner just past the seam still brakes the samples before it
	for k in n * 2:
		var i := posmod(n - 1 - k, n)
		var next := profile[(i + 1) % n]
		profile[i] = minf(profile[i], sqrt(next * next + brake_gain))
	return profile


func profile_speed(profile: PackedFloat32Array, s: float) -> float:
	return profile[_index(s)]


## Global search — only for a bot that just teleported. Everything else uses track_offset.
func closest_offset(pos: Vector3) -> float:
	return _curve.get_closest_offset(pos)


## Nearest offset to pos within a forward-biased window around s_hint. Local on purpose: where the
## line passes near itself (bridge, crossover) a global search would jump to the other pass.
func track_offset(pos: Vector3, s_hint: float, window: float) -> float:
	var best := s_hint
	var best_dist := INF
	var s := s_hint - window * 0.25
	while s <= s_hint + window:
		var dist := point_at(s).distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = s
		s += sample_spacing
	# Project onto the line's direction so progress isn't quantized to the sample spacing
	var along := (pos - point_at(best)).dot(Vector3.UP.cross(right_at(best)))
	return wrap_offset(best + clampf(along, -sample_spacing, sample_spacing))


## Road-only navmesh paths through every checkpoint, back to the first when closed. An unreachable
## checkpoint fails loudly and is bridged straight, so the line still exists to debug.
func _corridor(road_region: RID, checkpoints: PackedVector3Array) -> PackedVector3Array:
	var map := NavigationServer3D.region_get_map(road_region)
	var snapped := PackedVector3Array()
	for checkpoint in checkpoints:
		snapped.append(NavigationServer3D.region_get_closest_point(road_region, checkpoint))
	var count := snapped.size()
	var corridor := PackedVector3Array([snapped[0]])
	for i in (count if closed else count - 1):
		var from := snapped[i]
		var to := snapped[(i + 1) % count]
		var path := NavigationServer3D.map_get_path(map, from, to, true, UtilsConstants.NAV_LAYER_ROAD)
		if path.is_empty() or path[path.size() - 1].distance_to(to) > sample_spacing:
			push_error("NPCRacingLine: no road navmesh path from checkpoint %d to %d, bridged straight" % [i, (i + 1) % count])
			path = PackedVector3Array([from, to])
		corridor.append_array(path.slice(1))
	return corridor


## The polyline re-cut into points sample_spacing apart. A closed line drops its end, which is
## its start again.
func _resample(polyline: PackedVector3Array) -> PackedVector3Array:
	var points := PackedVector3Array([polyline[0]])
	var since_last := 0.0
	for i in range(1, polyline.size()):
		var a := polyline[i - 1]
		var b := polyline[i]
		var seg := a.distance_to(b)
		var t := sample_spacing - since_last
		while t <= seg:
			points.append(a.lerp(b, t / seg))
			t += sample_spacing
		since_last = seg - (t - sample_spacing)
	var end := polyline[polyline.size() - 1]
	if closed:
		while points.size() > 2 and points[points.size() - 1].distance_to(points[0]) < sample_spacing * 0.5:
			points.remove_at(points.size() - 1)
	elif points[points.size() - 1].distance_to(end) > sample_spacing * 0.5:
		points.append(end)
	return points


## One Laplacian pass, each point clamped back onto the road. The funnel path already touches
## corner insides; this rounds entry and exit while the clamp holds the apex on the asphalt.
func _smooth(points: PackedVector3Array, road_region: RID) -> PackedVector3Array:
	var n := points.size()
	var smoothed := points.duplicate()
	for i in n:
		if !closed and (i == 0 or i == n - 1):
			continue
		var mid := (points[posmod(i - 1, n)] + points[(i + 1) % n]) * 0.5
		smoothed[i] = NavigationServer3D.region_get_closest_point(road_region, points[i].lerp(mid, 0.5))
	return smoothed


## Catmull-Rom through the points, as Bezier handles.
func _fit_curve(points: PackedVector3Array) -> void:
	_curve.closed = closed
	var n := points.size()
	for i in n:
		var prev := points[posmod(i - 1, n)] if closed or i > 0 else points[i]
		var next := points[(i + 1) % n] if closed or i < n - 1 else points[i]
		var handle := (next - prev) / 6.0
		_curve.add_point(points[i], -handle, handle)


func _bake_samples(road_region: RID, corner_grip: float, max_half_width: float) -> void:
	for i in int(get_length() / sample_spacing) + 1:
		var s := i * sample_spacing
		var lead := point_at(s) - point_at(s - sample_spacing)
		var trail := point_at(s + sample_spacing) - point_at(s)
		lead.y = 0.0
		trail.y = 0.0
		var curvature := lead.signed_angle_to(trail, Vector3.UP) / sample_spacing
		_curvature.append(curvature)
		_corner_speed.append(sqrt(corner_grip / maxf(absf(curvature), MIN_CURVATURE)))
		var right := right_at(s)
		_room_right.append(_room(road_region, point_at(s), right, max_half_width))
		_room_left.append(_room(road_region, point_at(s), -right, max_half_width))


## How far from origin along dir the road continues, marched in ROOM_STEPs so a parallel road
## past a median never counts as room.
func _room(road_region: RID, origin: Vector3, dir: Vector3, max_half_width: float) -> float:
	var room := 0.0
	while room + ROOM_STEP <= max_half_width:
		var probe := origin + dir * (room + ROOM_STEP)
		var on_road := NavigationServer3D.region_get_closest_point(road_region, probe)
		if Vector2(on_road.x - probe.x, on_road.z - probe.z).length() > ROOM_STEP * 0.5:
			break
		room += ROOM_STEP
	return room


func _index(s: float) -> int:
	var i := int(round(wrap_offset(s) / sample_spacing))
	return i % _curvature.size() if closed else mini(i, _curvature.size() - 1)
