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


@onready var mesh_inst: MeshInstance3D = %MeshInstance3D
@onready var col_shape: CollisionShape3D = %CollisionShape3D


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
		return

	var length := curve.get_baked_length()
	var half := road_width * 0.5
	var u_right := road_width / uv_tile_size

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
		var right := xf.basis.x * half
		var l := xf.origin - right
		var r := xf.origin + right
		var v := sampled / uv_tile_size

		if not first:
			# Wound so the top face normal points +Y. generate_normals()
			# recomputes from this winding.
			st.set_uv(Vector2(0.0, prev_v)); st.add_vertex(prev_l)
			st.set_uv(Vector2(u_right, v)); st.add_vertex(r)
			st.set_uv(Vector2(u_right, prev_v)); st.add_vertex(prev_r)

			st.set_uv(Vector2(0.0, prev_v)); st.add_vertex(prev_l)
			st.set_uv(Vector2(0.0, v)); st.add_vertex(l)
			st.set_uv(Vector2(u_right, v)); st.add_vertex(r)

		prev_l = l
		prev_r = r
		prev_v = v
		first = false

		if sampled >= length:
			break
		d += step

	st.generate_normals()
	st.generate_tangents()

	var m := st.commit()
	mesh_inst.mesh = m
	col_shape.shape = m.create_trimesh_shape()
	_apply_material()


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
