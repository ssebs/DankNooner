@tool
## Generates a drivable road mesh + trimesh collider by extruding a flat
## strip along this node's Curve3D. Edit the curve in the viewport; the mesh
## rebuilds live. Set collision layers/masks on the child StaticBody3D.
class_name RoadPath extends Path3D

@export var road_width: float = 8.0:
	set(v):
		road_width = maxf(0.1, v)
		_rebuild()

## Sample spacing along the curve, in meters. Smaller = smoother curves.
@export var step: float = 1.0:
	set(v):
		step = maxf(0.05, v)
		_rebuild()

## Rounds off curve corners by setting each interior point's in/out handles
## tangent to its neighbors. 0 = sharp corners, 1 = fully rounded. Setting this
## edits the curve, which emits curve_changed and rebuilds the mesh.
@export_range(0.0, 1.0) var smoothness: float = 0.25:
	set(v):
		smoothness = v
		smooth_curve()

## Point indices whose handles are zeroed instead of smoothed, keeping those
## segments straight (e.g. straightaways). Find an index by selecting the point
## in the viewport.
@export var sharp_points: Array[int] = []:
	set(v):
		sharp_points = v
		smooth_curve()

## Indices marking the START of a straight segment: the out-handle of that point
## and the in-handle of the next point are zeroed, flattening only that one
## segment while leaving each point's other tail smoothed.
@export var straight_segments: Array[int] = []:
	set(v):
		straight_segments = v
		smooth_curve()

## Like straight_segments, but halves the smoothing on that segment's handles
## instead of zeroing them — a gentler, straighter curve rather than fully flat.
@export var straighter_segments: Array[int] = []:
	set(v):
		straighter_segments = v
		smooth_curve()

## World meters per texture repeat. UVs are generated in meter units so the
## texture tiles uniformly along the road and across its width.
@export var uv_tile_size: float = 4.0:
	set(v):
		uv_tile_size = maxf(0.01, v)
		_rebuild()

@export var material: Material:
	set(v):
		material = v
		_apply_material()

## Runoff is a flat strip continuing outward from each road edge (sand/grass/
## etc), inheriting the road's height + banking. Width 0 = no runoff on that
## side. Material null = untextured. Walls sit at the OUTER edge of the runoff
## (the road edge if width is 0); height 0 = no wall.
@export_group("Left Side")
@export var left_runoff_width: float = 0.0:
	set(v):
		left_runoff_width = maxf(0.0, v)
		_rebuild()
@export var left_runoff_material: Material:
	set(v):
		left_runoff_material = v
		_rebuild()
@export var left_wall_height: float = 0.0:
	set(v):
		left_wall_height = maxf(0.0, v)
		_rebuild()
@export var left_wall_material: Material:
	set(v):
		left_wall_material = v
		_rebuild()
## Segment indices (start point, same indexing as straight_segments) where the
## left wall is omitted, leaving a gap. Use on tight inner corners where the
## offset wall would otherwise fold into itself.
@export var left_wall_skip_segments: Array[int] = []:
	set(v):
		left_wall_skip_segments = v
		_rebuild()

@export_group("Right Side")
@export var right_runoff_width: float = 0.0:
	set(v):
		right_runoff_width = maxf(0.0, v)
		_rebuild()
@export var right_runoff_material: Material:
	set(v):
		right_runoff_material = v
		_rebuild()
@export var right_wall_height: float = 0.0:
	set(v):
		right_wall_height = maxf(0.0, v)
		_rebuild()
@export var right_wall_material: Material:
	set(v):
		right_wall_material = v
		_rebuild()
## See left_wall_skip_segments.
@export var right_wall_skip_segments: Array[int] = []:
	set(v):
		right_wall_skip_segments = v
		_rebuild()

@onready var mesh_inst: MeshInstance3D = %MeshInstance3D
@onready var col_shape: CollisionShape3D = %CollisionShape3D
@onready var left_runoff_mesh: MeshInstance3D = %LeftRunoff
@onready var left_runoff_col: CollisionShape3D = %LeftRunoffCol
@onready var right_runoff_mesh: MeshInstance3D = %RightRunoff
@onready var right_runoff_col: CollisionShape3D = %RightRunoffCol
@onready var left_wall_mesh: MeshInstance3D = %LeftWall
@onready var left_wall_col: CollisionShape3D = %LeftWallCol
@onready var right_wall_mesh: MeshInstance3D = %RightWall
@onready var right_wall_col: CollisionShape3D = %RightWallCol


func _ready() -> void:
	if not curve_changed.is_connected(_rebuild):
		curve_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	if not is_node_ready():
		return

	if curve == null or curve.point_count < 2:
		mesh_inst.mesh = null
		col_shape.shape = null
		_apply_feature(left_runoff_mesh, left_runoff_col, null, null)
		_apply_feature(right_runoff_mesh, right_runoff_col, null, null)
		_apply_feature(left_wall_mesh, left_wall_col, null, null)
		_apply_feature(right_wall_mesh, right_wall_col, null, null)
		return

	var half := road_width * 0.5

	# Road is the flat strip spanning the full width.
	var road := _build_flat_strip(-half, half)
	mesh_inst.mesh = road
	col_shape.shape = road.create_trimesh_shape()
	_apply_material()

	# Runoff continues outward from each road edge, sharing that edge so it's
	# seamless and inheriting the road's height + banking.
	var lr: ArrayMesh = (
		_build_flat_strip(-half - left_runoff_width, -half) if left_runoff_width > 0.0 else null
	)
	_apply_feature(left_runoff_mesh, left_runoff_col, lr, left_runoff_material)

	var rr: ArrayMesh = (
		_build_flat_strip(half, half + right_runoff_width) if right_runoff_width > 0.0 else null
	)
	_apply_feature(right_runoff_mesh, right_runoff_col, rr, right_runoff_material)

	# Walls stand at the outer edge of each runoff (road edge if no runoff).
	var lw: ArrayMesh = (
		_build_wall_strip(-(half + left_runoff_width), left_wall_height, left_wall_skip_segments)
		if left_wall_height > 0.0
		else null
	)
	_apply_feature(left_wall_mesh, left_wall_col, lw, left_wall_material)

	var rw: ArrayMesh = (
		_build_wall_strip(half + right_runoff_width, right_wall_height, right_wall_skip_segments)
		if right_wall_height > 0.0
		else null
	)
	_apply_feature(right_wall_mesh, right_wall_col, rw, right_wall_material)


## Builds a flat ribbon following the curve between two offsets, in meters along
## the road's right vector (left is negative). off_a must be <= off_b so the top
## face winds +Y. UVs are in world meters so the texture tiles continuously
## across the road and into the runoff.
func _build_flat_strip(off_a: float, off_b: float) -> ArrayMesh:
	var length := curve.get_baked_length()
	var u_a := off_a / uv_tile_size
	var u_b := off_b / uv_tile_size

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_v := 0.0
	var first := true
	var d := 0.0

	while true:
		var sampled := minf(d, length)
		var xf := curve.sample_baked_with_rotation(sampled, true, true)
		var l := xf.origin + xf.basis.x * off_a
		var r := xf.origin + xf.basis.x * off_b
		var v := sampled / uv_tile_size

		if not first:
			# Wound so the top face normal points +Y. generate_normals()
			# recomputes from this winding.
			st.set_uv(Vector2(u_a, prev_v))
			st.add_vertex(prev_l)
			st.set_uv(Vector2(u_b, v))
			st.add_vertex(r)
			st.set_uv(Vector2(u_b, prev_v))
			st.add_vertex(prev_r)

			st.set_uv(Vector2(u_a, prev_v))
			st.add_vertex(prev_l)
			st.set_uv(Vector2(u_a, v))
			st.add_vertex(l)
			st.set_uv(Vector2(u_b, v))
			st.add_vertex(r)

		prev_l = l
		prev_r = r
		prev_v = v
		first = false

		if sampled >= length:
			break
		d += step

	st.generate_normals()
	st.generate_tangents()
	return st.commit()


## Builds a vertical ribbon at `off` meters from the centerline, extruded up by
## `height` along the road's local up so it leans with banking. Emitted on both
## faces so it shows from either side; the trimesh collider is solid regardless.
func _build_wall_strip(off: float, height: float, skip_segments: Array[int]) -> ArrayMesh:
	var length := curve.get_baked_length()
	var u_top := height / uv_tile_size
	var side := signf(off)  # +1 right of centerline, -1 left
	var bounds := _segment_boundaries()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var prev_b := Vector3.ZERO
	var prev_t := Vector3.ZERO
	var prev_n := Vector3.ZERO
	var prev_v := 0.0
	var first := true
	var cur_seg := 0
	var d := 0.0

	while true:
		var sampled := minf(d, length)

		# Advance to the segment this sample falls in. Skipped segments emit
		# nothing and reset `first`, so the wall breaks into a fresh strip
		# afterward instead of bridging — and can't fold through itself on a
		# tight inner corner.
		while cur_seg + 1 < bounds.size() - 1 and sampled >= bounds[cur_seg + 1]:
			cur_seg += 1
		if cur_seg in skip_segments:
			first = true
			if sampled >= length:
				break
			d += step
			continue

		var xf := curve.sample_baked_with_rotation(sampled, true, true)
		var base := xf.origin + xf.basis.x * off
		var top := base + xf.basis.y * height
		var n := -xf.basis.x * side  # faces the track
		var v := sampled / uv_tile_size

		if not first:
			# Front faces (toward the track).
			st.set_normal(prev_n)
			st.set_uv(Vector2(prev_v, 0.0))
			st.add_vertex(prev_b)
			st.set_normal(prev_n)
			st.set_uv(Vector2(prev_v, u_top))
			st.add_vertex(prev_t)
			st.set_normal(n)
			st.set_uv(Vector2(v, u_top))
			st.add_vertex(top)

			st.set_normal(prev_n)
			st.set_uv(Vector2(prev_v, 0.0))
			st.add_vertex(prev_b)
			st.set_normal(n)
			st.set_uv(Vector2(v, u_top))
			st.add_vertex(top)
			st.set_normal(n)
			st.set_uv(Vector2(v, 0.0))
			st.add_vertex(base)

			# Back faces (reversed winding, same normals).
			st.set_normal(n)
			st.set_uv(Vector2(v, u_top))
			st.add_vertex(top)
			st.set_normal(prev_n)
			st.set_uv(Vector2(prev_v, u_top))
			st.add_vertex(prev_t)
			st.set_normal(prev_n)
			st.set_uv(Vector2(prev_v, 0.0))
			st.add_vertex(prev_b)

			st.set_normal(n)
			st.set_uv(Vector2(v, 0.0))
			st.add_vertex(base)
			st.set_normal(n)
			st.set_uv(Vector2(v, u_top))
			st.add_vertex(top)
			st.set_normal(prev_n)
			st.set_uv(Vector2(prev_v, 0.0))
			st.add_vertex(prev_b)

		prev_b = base
		prev_t = top
		prev_n = n
		prev_v = v
		first = false

		if sampled >= length:
			break
		d += step

	st.generate_tangents()
	return st.commit()


## Baked-length offset of each curve segment boundary, so a sampled distance can
## be mapped back to its segment index (same indexing as straight_segments).
## Integrates per-segment arc length directly, which stays correct where the
## track loops near itself (unlike get_closest_offset).
func _segment_boundaries() -> PackedFloat32Array:
	var bounds := PackedFloat32Array()
	bounds.append(0.0)
	var acc := 0.0
	const SUBDIV := 16
	for i in curve.point_count - 1:
		var prev := curve.sample(i, 0.0)
		for j in range(1, SUBDIV + 1):
			var p := curve.sample(i, float(j) / SUBDIV)
			acc += prev.distance_to(p)
			prev = p
		bounds.append(acc)
	# Closing segment (last point → first) spans up to the full baked length.
	if curve.closed:
		bounds.append(curve.get_baked_length())
	return bounds


## Assigns a generated mesh + trimesh collider to a side feature, or clears both
## when mesh is null. Material is optional.
func _apply_feature(
	mi: MeshInstance3D, cs: CollisionShape3D, mesh: ArrayMesh, mat: Material
) -> void:
	mi.mesh = mesh
	cs.shape = mesh.create_trimesh_shape() if mesh != null else null
	if mesh != null and mat != null:
		mesh.surface_set_material(0, mat)


func smooth_curve() -> void:
	# Setter can fire during scene load before the curve is assigned.
	if curve == null:
		return
	for i in range(1, curve.point_count - 1):
		if i in sharp_points:
			curve.set_point_in(i, Vector3.ZERO)
			curve.set_point_out(i, Vector3.ZERO)
			continue
		var segment_in := curve.get_point_position(i) - curve.get_point_position(i - 1)
		var segment_out := curve.get_point_position(i + 1) - curve.get_point_position(i)
		var tangent := (segment_in.normalized() + segment_out.normalized()).normalized()
		curve.set_point_in(i, -tangent * segment_in.length() * smoothness)
		curve.set_point_out(i, tangent * segment_out.length() * smoothness)

	# Per-segment overrides, applied after smoothing so they win on shared points.
	for i in straighter_segments:
		curve.set_point_out(i, curve.get_point_out(i) * 0.5)
		curve.set_point_in(i + 1, curve.get_point_in(i + 1) * 0.5)

	for i in straight_segments:
		curve.set_point_out(i, Vector3.ZERO)
		curve.set_point_in(i + 1, Vector3.ZERO)


func _apply_material() -> void:
	if is_node_ready() and mesh_inst.mesh != null:
		mesh_inst.mesh.surface_set_material(0, material)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if curve == null or curve.point_count < 2:
		warnings.append("Curve needs at least 2 points to build a road.")
	return warnings
