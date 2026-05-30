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

	# Catmull-Rom needs the neighbors on either side of the segment.
	var p0 := _point_pos(points, i - 1)
	var p1 := owner_pt.position
	var p2 := next_pt.position
	var p3 := _point_pos(points, i + 2)
	var up_a := owner_pt.transform.basis.y.normalized()
	var up_b := next_pt.transform.basis.y.normalized()

	var subdiv: int = maxi(1, int(round(p1.distance_to(p2) / step)))

	# Per-segment curve strength: the Track's global tension slackens every
	# segment; the owner point's curviness flattens just this one toward its
	# chord. Both only scale the tangent MAGNITUDE, so endpoint directions (and
	# thus the shared boundary frames) are unchanged — gap-free for curviness > 0.
	var factor := (1.0 - tension) * owner_pt.curviness

	var frames: Array[Transform3D] = []
	var forward := (p2 - p1).normalized()
	for j in subdiv + 1:
		var t := float(j) / subdiv
		var pos := _hermite(p0, p1, p2, p3, t, factor)
		var tangent := _hermite_tangent(p0, p1, p2, p3, t, factor)
		# Guard a near-zero tangent (straight chord / cusp) which would normalize
		# to NaN and spike the mesh — reuse the last good forward.
		if tangent.length_squared() > 1e-6:
			forward = tangent.normalized()
		var up := up_a.slerp(up_b, t)
		frames.append(_frame(pos, forward, up))

	var half := road_width * 0.5

	# Road: full-width flat strip. Null cfg falls through to the Track road
	# defaults.
	_commit_feature(_build_flat_strip(frames, _const(subdiv, -half), _const(subdiv, half)), null)

	# Runoff: width lerps a->b so adjacent segments meet seamlessly at the shared
	# boundary point. off_a must stay <= off_b for +Y winding.
	if owner_pt.left_runoff_width > 0.0 or next_pt.left_runoff_width > 0.0:
		var outer := _lerp_offsets(
			subdiv, -half, -half, owner_pt.left_runoff_width, next_pt.left_runoff_width, -1.0
		)
		_commit_feature(
			_build_flat_strip(frames, outer, _const(subdiv, -half)), owner_pt.left_runoff
		)
	if owner_pt.right_runoff_width > 0.0 or next_pt.right_runoff_width > 0.0:
		var outer := _lerp_offsets(
			subdiv, half, half, owner_pt.right_runoff_width, next_pt.right_runoff_width, 1.0
		)
		_commit_feature(
			_build_flat_strip(frames, _const(subdiv, half), outer), owner_pt.right_runoff
		)

	# Walls stand at the outer edge of each runoff; gated by the owner point so a
	# zero-height corner drops its wall. Height/offset lerp a->b for continuity.
	if owner_pt.left_wall_height > 0.0:
		var off := _lerp_offsets(
			subdiv, -half, -half, owner_pt.left_runoff_width, next_pt.left_runoff_width, -1.0
		)
		var hgt := _lerp_floats(subdiv, owner_pt.left_wall_height, next_pt.left_wall_height)
		_commit_feature(_build_wall_strip(frames, off, hgt), owner_pt.left_wall)
	if owner_pt.right_wall_height > 0.0:
		var off := _lerp_offsets(
			subdiv, half, half, owner_pt.right_runoff_width, next_pt.right_runoff_width, 1.0
		)
		var hgt := _lerp_floats(subdiv, owner_pt.right_wall_height, next_pt.right_wall_height)
		_commit_feature(_build_wall_strip(frames, off, hgt), owner_pt.right_wall)


## Position of points[idx], wrapping for closed loops or clamping for open ones
## (clamping makes the end Catmull-Rom tangents mirror the adjacent segment).
func _point_pos(points: Array[TrackPoint], idx: int) -> Vector3:
	var count := points.size()
	if closed:
		return points[(idx % count + count) % count].position
	return points[clampi(idx, 0, count - 1)].position


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
