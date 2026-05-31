@tool
## Marker-driven track builder. Collects its ordered TrackPoint children and
## regenerates road + runoff + wall geometry along the spline they define.
##
## Banking comes from each TrackPoint's ROLL (its up-vector); the path tangent
## always comes from the spline. Each segment commits its own StaticBody3D +
## MeshInstance3D per feature, so per-segment material/collision is free. The
## generated nodes are owner-less — they are NOT saved to the .tscn and rebuild
## on _ready.
class_name Track extends Node3D

@export var road_width: float = 12.0:
	set(v):
		road_width = maxf(0.1, v)
		queue_rebuild()

## Approximate sample spacing in meters. Smaller = smoother curves.
@export var step: float = 1.0:
	set(v):
		step = maxf(0.05, v)
		queue_rebuild()

## Catmull-Rom tightness. 0 = standard Catmull-Rom; higher slackens the curve
## toward straight chords between points.
@export_range(0.0, 1.0) var tension: float = 0.0:
	set(v):
		tension = v
		queue_rebuild()

## Wrap the spline from the last point back to the first.
@export var closed: bool = false:
	set(v):
		closed = v
		queue_rebuild()

@export_group("Road Defaults")
## Default texture for road + any side feature that doesn't override it.
@export var texture: Texture2D = DEFAULT_TEXTURE:
	set(v):
		texture = v
		queue_rebuild()
@export var road_preset: MaterialPresets.Preset = MaterialPresets.Preset.DARK_GRAY:
	set(v):
		road_preset = v
		queue_rebuild()
@export_flags_3d_physics var collision_layer: int = 1:
	set(v):
		collision_layer = v
		queue_rebuild()

@export_group("Ground Apron")
## Generate a ground skirt beyond each runoff that ramps down to `ground_y`, tying
## the elevated track into the surrounding ground. Uses that side's runoff
## material so it blends. Off by default.
@export var ground_apron: bool = false:
	set(v):
		ground_apron = v
		queue_rebuild()
## World height the apron ramps down to — your surrounding flat ground level.
@export var ground_y: float = 0.0:
	set(v):
		ground_y = v
		queue_rebuild()
## Max horizontal reach of the apron outward from the runoff/road edge.
@export var apron_width: float = 30.0:
	set(v):
		apron_width = maxf(0.0, v)
		queue_rebuild()

const DEFAULT_TEXTURE := preload(
	"res://levels/assets/kenney_prototype-textures/PNG/Dark/texture_04.png"
)

var _building := false
var _rebuild_queued := false


func _ready() -> void:
	if not child_order_changed.is_connected(queue_rebuild):
		child_order_changed.connect(queue_rebuild)
	queue_rebuild()


## Requests a rebuild at idle. Deferring keeps all scene-tree mutation out of
## notifications/signals/load/teardown, which otherwise crashes the editor.
func queue_rebuild() -> void:
	# Ignore the child_order_changed our own add/remove fires during a build.
	if _building or _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


## Regenerates all geometry from the current TrackPoint children.
func rebuild() -> void:
	_rebuild_queued = false
	if _building or not is_node_ready():
		return
	_building = true

	_clear_generated()

	var points := _track_points()
	if points.size() >= 2:
		var seg_count := points.size() if closed else points.size() - 1
		for i in seg_count:
			_build_segment(points, i)
		# Sharp points get an apex arc bridging their two (trimmed) straight chords.
		for k in points.size():
			if points[k].sharp:
				_build_corner(points, k)

	_building = false


## Ordered TrackPoint children.
func _track_points() -> Array[TrackPoint]:
	var pts: Array[TrackPoint] = []
	for child in get_children():
		if child is TrackPoint:
			pts.append(child)
	return pts


## Frees previously generated, owner-less geometry (tagged with meta "generated")
## so user-authored children (the TrackPoints) are never touched.
func _clear_generated() -> void:
	for child in get_children():
		if child.has_meta("generated"):
			remove_child(child)
			child.free()


# --- Segment build -----------------------------------------------------------


func _build_segment(points: Array[TrackPoint], i: int) -> void:
	var count := points.size()
	var owner_pt := points[i]
	var next_pt := points[(i + 1) % count]

	# Catmull-Rom needs the neighbors on either side of the segment. A sharp
	# endpoint clamps its neighbor to itself so the tangent there points straight
	# down this segment's chord (the apex arc, built separately, joins the gap).
	var p0 := owner_pt.position if owner_pt.sharp else _point_pos(points, i - 1)
	var p1 := owner_pt.position
	var p2 := next_pt.position
	var p3 := next_pt.position if next_pt.sharp else _point_pos(points, i + 2)
	var up_a := owner_pt.transform.basis.y.normalized()
	var up_b := next_pt.transform.basis.y.normalized()

	# Trim the segment back to each sharp endpoint's arc tangent point so the
	# straight chord ends exactly where the apex arc begins.
	var chord_len := p1.distance_to(p2)
	var t_start := (_corner_trim_length(points, i) / chord_len) if owner_pt.sharp else 0.0
	var t_end := (
		1.0 - _corner_trim_length(points, (i + 1) % count) / chord_len if next_pt.sharp else 1.0
	)
	var span := t_end - t_start

	var subdiv: int = maxi(1, int(round(chord_len * span / step)))

	# Per-segment curve strength: the Track's global tension slackens every
	# segment; the owner point's curviness flattens just this one toward its
	# chord. Both only scale the tangent MAGNITUDE, so endpoint directions (and
	# thus the shared boundary frames) are unchanged — gap-free for curviness > 0.
	var factor := (1.0 - tension) * owner_pt.curviness

	var frames: Array[Transform3D] = []
	var forward := (p2 - p1).normalized()
	for j in subdiv + 1:
		var t := t_start + span * (float(j) / subdiv)
		var pos := _hermite(p0, p1, p2, p3, t, factor)
		var tangent := _hermite_tangent(p0, p1, p2, p3, t, factor)
		# Guard a near-zero tangent (straight chord / cusp) which would normalize
		# to NaN and spike the mesh — reuse the last good forward.
		if tangent.length_squared() > 1e-6:
			forward = tangent.normalized()
		var up := up_a.slerp(up_b, t)
		frames.append(_frame(pos, forward, up))

	var half := road_width * 0.5

	# Trimming shifts the boundaries inward, so the per-side widths/heights that
	# lerp a->b must be re-evaluated at the trimmed t range to stay seam-tight.
	var lw_a := lerpf(owner_pt.left_runoff_width, next_pt.left_runoff_width, t_start)
	var lw_b := lerpf(owner_pt.left_runoff_width, next_pt.left_runoff_width, t_end)
	var rw_a := lerpf(owner_pt.right_runoff_width, next_pt.right_runoff_width, t_start)
	var rw_b := lerpf(owner_pt.right_runoff_width, next_pt.right_runoff_width, t_end)

	# Road: full-width flat strip. Null cfg falls through to the Track road
	# defaults.
	_commit_feature(_build_flat_strip(frames, _const(subdiv, -half), _const(subdiv, half)), null)

	# Runoff: width lerps a->b so adjacent segments meet seamlessly at the shared
	# boundary point. off_a must stay <= off_b for +Y winding.
	if lw_a > 0.0 or lw_b > 0.0:
		var outer := _lerp_offsets(subdiv, -half, -half, lw_a, lw_b, -1.0)
		_commit_feature(
			_build_flat_strip(frames, outer, _const(subdiv, -half)), owner_pt.left_runoff
		)
	if rw_a > 0.0 or rw_b > 0.0:
		var outer := _lerp_offsets(subdiv, half, half, rw_a, rw_b, 1.0)
		_commit_feature(
			_build_flat_strip(frames, _const(subdiv, half), outer), owner_pt.right_runoff
		)

	# Apron: skirt from each runoff/road outer edge down to flat ground.
	if ground_apron and apron_width > 0.0:
		var left_edge := _lerp_offsets(subdiv, -half, -half, lw_a, lw_b, -1.0)
		_commit_feature(_build_apron_strip(frames, left_edge, -1.0), owner_pt.left_runoff)
		var right_edge := _lerp_offsets(subdiv, half, half, rw_a, rw_b, 1.0)
		_commit_feature(_build_apron_strip(frames, right_edge, 1.0), owner_pt.right_runoff)

	# Walls stand at the outer edge of each runoff; gated by the owner point so a
	# zero-height corner drops its wall. Height/offset lerp a->b for continuity.
	if owner_pt.left_wall_height > 0.0:
		var off := _lerp_offsets(subdiv, -half, -half, lw_a, lw_b, -1.0)
		var ha := lerpf(owner_pt.left_wall_height, next_pt.left_wall_height, t_start)
		var hb := lerpf(owner_pt.left_wall_height, next_pt.left_wall_height, t_end)
		_commit_feature(_build_wall_strip(frames, off, _lerp_floats(subdiv, ha, hb)), owner_pt.left_wall)
	if owner_pt.right_wall_height > 0.0:
		var off := _lerp_offsets(subdiv, half, half, rw_a, rw_b, 1.0)
		var ha := lerpf(owner_pt.right_wall_height, next_pt.right_wall_height, t_start)
		var hb := lerpf(owner_pt.right_wall_height, next_pt.right_wall_height, t_end)
		_commit_feature(
			_build_wall_strip(frames, off, _lerp_floats(subdiv, ha, hb)), owner_pt.right_wall
		)


## Position of points[idx], wrapping for closed loops or clamping for open ones
## (clamping makes the end Catmull-Rom tangents mirror the adjacent segment).
func _point_pos(points: Array[TrackPoint], idx: int) -> Vector3:
	var count := points.size()
	if closed:
		return points[(idx % count + count) % count].position
	return points[clampi(idx, 0, count - 1)].position


# --- Sharp corners -----------------------------------------------------------


## Distance along each chord from a sharp point to its arc tangent point (the
## fillet tangent length T = radius * tan(deflection/2)), or 0 if point k is not a
## valid sharp corner. Auto-shrunk so both tangent points stay within their
## chords (leaving room for a neighbouring corner). Used by both the segment
## trimmer and the arc builder so they agree on where the straight meets the arc.
func _corner_trim_length(points: Array[TrackPoint], k: int) -> float:
	var pt := points[k]
	if not pt.sharp or pt.corner_radius <= 0.0:
		return 0.0
	var count := points.size()
	# Open-track endpoints have no incoming/outgoing chord — can't be filleted.
	if not closed and (k == 0 or k == count - 1):
		return 0.0
	var prev_pos := _point_pos(points, k - 1)
	var next_pos := _point_pos(points, k + 1)
	var din := pt.position - prev_pos
	var dout := next_pos - pt.position
	if din.length_squared() < 1e-6 or dout.length_squared() < 1e-6:
		return 0.0
	# Use the plan-view (horizontal) turn angle so a steep grade through the corner
	# doesn't inflate the fillet length.
	var din_h := Vector3(din.x, 0.0, din.z)
	var dout_h := Vector3(dout.x, 0.0, dout.z)
	if din_h.length_squared() < 1e-6 or dout_h.length_squared() < 1e-6:
		return 0.0
	var delta := acos(clampf(din_h.normalized().dot(dout_h.normalized()), -1.0, 1.0))
	# Near-straight (no real corner) or near-180 U-turn (tangent length explodes).
	if delta < 0.01 or delta > PI - 0.01:
		return 0.0
	var trim := pt.corner_radius * tan(delta * 0.5)
	return minf(trim, minf(0.49 * din.length(), 0.49 * dout.length()))


## Commits the road + runoff arc that joins a sharp point's two straight chords.
## Tangent to both chords and built in their shared (3D) plane, so it descends
## through the turn — the Corkscrew case. Walls are not filled here (known gap).
func _build_corner(points: Array[TrackPoint], k: int) -> void:
	var t := _corner_trim_length(points, k)
	if t <= 0.0:
		return
	var count := points.size()
	var pt := points[k]
	var prev_pt := points[(k - 1 + count) % count]
	var next_pt := points[(k + 1) % count]
	var din := (pt.position - prev_pt.position).normalized()
	var dout := (next_pt.position - pt.position).normalized()
	var pa := pt.position - din * t
	var pb := pt.position + dout * t
	var up := pt.transform.basis.y.normalized()

	# Quadratic Bézier fillet through pa -> corner -> pb. Tangent to din at pa and
	# dout at pb (pa-pt is along din, pb-pt along dout), so it joins the trimmed
	# chords smoothly. Y just interpolates, so a corner on a grade can't plunge the
	# way a circular arc in the chords' (tilted) plane would.
	var subdiv: int = maxi(2, int(round((pa.distance_to(pt.position) + pt.position.distance_to(pb)) / step)))
	var frames: Array[Transform3D] = []
	var forward := din
	for j in subdiv + 1:
		var s := float(j) / subdiv
		var oms := 1.0 - s
		var pos := oms * oms * pa + 2.0 * oms * s * pt.position + s * s * pb
		var tangent := 2.0 * oms * (pt.position - pa) + 2.0 * s * (pb - pt.position)
		if tangent.length_squared() > 1e-6:
			forward = tangent.normalized()
		frames.append(_frame(pos, forward, up))

	var half := road_width * 0.5
	_commit_feature(_build_flat_strip(frames, _const(subdiv, -half), _const(subdiv, half)), null)

	# Match the trimmed segments' runoff widths at the tangent points so the arc's
	# edges line up with the chords it bridges (t_in/t_out are those segments' t
	# at pa/pb).
	var t_in := 1.0 - t / pt.position.distance_to(prev_pt.position)
	var t_out := t / pt.position.distance_to(next_pt.position)
	var lw_a := lerpf(prev_pt.left_runoff_width, pt.left_runoff_width, t_in)
	var lw_b := lerpf(pt.left_runoff_width, next_pt.left_runoff_width, t_out)
	if lw_a > 0.0 or lw_b > 0.0:
		var outer := _lerp_offsets(subdiv, -half, -half, lw_a, lw_b, -1.0)
		_commit_feature(_build_flat_strip(frames, outer, _const(subdiv, -half)), pt.left_runoff)
	var rw_a := lerpf(prev_pt.right_runoff_width, pt.right_runoff_width, t_in)
	var rw_b := lerpf(pt.right_runoff_width, next_pt.right_runoff_width, t_out)
	if rw_a > 0.0 or rw_b > 0.0:
		var outer := _lerp_offsets(subdiv, half, half, rw_a, rw_b, 1.0)
		_commit_feature(_build_flat_strip(frames, _const(subdiv, half), outer), pt.right_runoff)

	if ground_apron and apron_width > 0.0:
		var left_edge := _lerp_offsets(subdiv, -half, -half, lw_a, lw_b, -1.0)
		_commit_feature(_build_apron_strip(frames, left_edge, -1.0), pt.left_runoff)
		var right_edge := _lerp_offsets(subdiv, half, half, rw_a, rw_b, 1.0)
		_commit_feature(_build_apron_strip(frames, right_edge, 1.0), pt.right_runoff)


# --- Spline math -------------------------------------------------------------


## Cardinal spline position between p1 and p2. `factor` scales the tangents
## (1 = Catmull-Rom, 0 = straight chord).
func _hermite(
	p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float, factor: float
) -> Vector3:
	var m1 := (p2 - p0) * 0.5 * factor
	var m2 := (p3 - p1) * 0.5 * factor
	var t2 := t * t
	var t3 := t2 * t
	return (
		(2.0 * t3 - 3.0 * t2 + 1.0) * p1
		+ (t3 - 2.0 * t2 + t) * m1
		+ (-2.0 * t3 + 3.0 * t2) * p2
		+ (t3 - t2) * m2
	)


## Derivative of _hermite — the un-normalized path tangent.
func _hermite_tangent(
	p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float, factor: float
) -> Vector3:
	var m1 := (p2 - p0) * 0.5 * factor
	var m2 := (p3 - p1) * 0.5 * factor
	var t2 := t * t
	return (
		(6.0 * t2 - 6.0 * t) * p1
		+ (3.0 * t2 - 4.0 * t + 1.0) * m1
		+ (-6.0 * t2 + 6.0 * t) * p2
		+ (3.0 * t2 - 2.0 * t) * m2
	)


## Builds a road frame: basis.x = right, basis.y = up, basis.z = back (matching
## Curve3D's sample_baked_with_rotation, so the strip builders carry over).
func _frame(pos: Vector3, forward: Vector3, up: Vector3) -> Transform3D:
	var x_axis := forward.cross(up).normalized()
	var z_axis := -forward
	var y_axis := z_axis.cross(x_axis).normalized()
	return Transform3D(Basis(x_axis, y_axis, z_axis), pos)


# --- Offset helpers (per-sample, parallel to frames) -------------------------


## Constant offset array of length subdiv + 1.
func _const(subdiv: int, value: float) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	for j in subdiv + 1:
		arr.append(value)
	return arr


## Offsets from `base` extended outward by a width that lerps a->b, signed for
## the side (-1 left, +1 right).
func _lerp_offsets(
	subdiv: int, base_a: float, base_b: float, width_a: float, width_b: float, side: float
) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	for j in subdiv + 1:
		var t := float(j) / subdiv
		var base := lerpf(base_a, base_b, t)
		var width := lerpf(width_a, width_b, t)
		arr.append(base + side * width)
	return arr


func _lerp_floats(subdiv: int, a: float, b: float) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	for j in subdiv + 1:
		arr.append(lerpf(a, b, float(j) / subdiv))
	return arr


# --- Geometry (adapted from RoadPath; triplanar materials drop the UV math) ---


## Flat ribbon between per-sample offsets along each frame's right vector.
## offs_a <= offs_b so the top face winds +Y.
func _build_flat_strip(
	frames: Array[Transform3D], offs_a: PackedFloat32Array, offs_b: PackedFloat32Array
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var first := true

	for j in frames.size():
		var xf := frames[j]
		var l := xf.origin + xf.basis.x * offs_a[j]
		var r := xf.origin + xf.basis.x * offs_b[j]

		if not first:
			st.add_vertex(prev_l)
			st.add_vertex(r)
			st.add_vertex(prev_r)

			st.add_vertex(prev_l)
			st.add_vertex(l)
			st.add_vertex(r)

		prev_l = l
		prev_r = r
		first = false

	st.generate_normals()
	return st.commit()


## Ground skirt from a per-sample inner edge (`inner_offs` along each frame's
## right vector) outward to FLAT ground at `ground_y`. The outer edge steps out
## horizontally by `apron_width` and snaps to `ground_y`, so it follows banking at
## the road edge but levels off into the surrounding ground. `side` (-1 left / +1
## right) picks the outward direction and keeps the top face winding +Y.
func _build_apron_strip(
	frames: Array[Transform3D], inner_offs: PackedFloat32Array, side: float
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var first := true

	for j in frames.size():
		var xf := frames[j]
		var inner := xf.origin + xf.basis.x * inner_offs[j]
		# Outward direction projected flat so the skirt grades toward level ground.
		var h_right := Vector3(xf.basis.x.x, 0.0, xf.basis.x.z)
		if h_right.length_squared() < 1e-6:
			h_right = Vector3(xf.basis.z.x, 0.0, xf.basis.z.z)
		h_right = h_right.normalized()
		var outer := inner + h_right * side * apron_width
		outer.y = ground_y
		# Order edges so the lower-x vertex is "l" (matches _build_flat_strip +Y).
		var l := inner if side > 0.0 else outer
		var r := outer if side > 0.0 else inner

		if not first:
			st.add_vertex(prev_l)
			st.add_vertex(r)
			st.add_vertex(prev_r)

			st.add_vertex(prev_l)
			st.add_vertex(l)
			st.add_vertex(r)

		prev_l = l
		prev_r = r
		first = false

	st.generate_normals()
	return st.commit()


## Vertical ribbon at per-sample offset `off`, extruded up by per-sample
## `height` along each frame's up so it leans with banking. Double-sided.
func _build_wall_strip(
	frames: Array[Transform3D], off: PackedFloat32Array, height: PackedFloat32Array
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var prev_b := Vector3.ZERO
	var prev_t := Vector3.ZERO
	var prev_n := Vector3.ZERO
	var first := true

	for j in frames.size():
		var xf := frames[j]
		var side := signf(off[j])  # +1 right of centerline, -1 left
		var base := xf.origin + xf.basis.x * off[j]
		var top := base + xf.basis.y * height[j]
		var n := -xf.basis.x * side  # faces the track

		if not first:
			# Front faces (toward the track).
			st.set_normal(prev_n)
			st.add_vertex(prev_b)
			st.set_normal(prev_n)
			st.add_vertex(prev_t)
			st.set_normal(n)
			st.add_vertex(top)

			st.set_normal(prev_n)
			st.add_vertex(prev_b)
			st.set_normal(n)
			st.add_vertex(top)
			st.set_normal(n)
			st.add_vertex(base)

			# Back faces (reversed winding, same normals).
			st.set_normal(n)
			st.add_vertex(top)
			st.set_normal(prev_n)
			st.add_vertex(prev_t)
			st.set_normal(prev_n)
			st.add_vertex(prev_b)

			st.set_normal(n)
			st.add_vertex(base)
			st.set_normal(n)
			st.add_vertex(top)
			st.set_normal(prev_n)
			st.add_vertex(prev_b)

		prev_b = base
		prev_t = top
		prev_n = n
		first = false

	return st.commit()


# --- Feature commit ----------------------------------------------------------


## Commits a generated mesh as a StaticBody3D (mesh + trimesh collider) child.
## cfg supplies per-side material/collision; null falls back to road defaults.
func _commit_feature(mesh: ArrayMesh, cfg: SurfaceConfig) -> void:
	if mesh == null or mesh.get_surface_count() == 0:
		return

	var body := StaticBody3D.new()
	body.collision_layer = cfg.collision_layer if cfg else collision_layer
	body.set_meta("generated", true)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var preset: MaterialPresets.Preset = cfg.material_preset if cfg else road_preset
	var tex: Texture2D = cfg.texture if cfg and cfg.texture else texture
	mi.set_surface_override_material(0, MaterialPresets.make_material(preset, tex))
	body.add_child(mi)

	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)

	add_child(body)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if _track_points().size() < 2:
		warnings.append("Track needs at least 2 TrackPoint children to build a road.")
	return warnings
