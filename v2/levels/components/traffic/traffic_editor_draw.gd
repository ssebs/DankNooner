@tool
class_name TrafficEditorDraw extends RefCounted

## Collects the traffic editor preview as flat ribbons, then writes them into one mesh. Rebuilt
## only when the network changes, so it stays on screen without any per-frame drawing.

const WIDTH := 0.3
const ARROW_SIZE := 1.0
const MARKER_RADIUS := 1.0

var _verts := PackedVector3Array()
var _colors := PackedColorArray()


func line(from: Vector3, to: Vector3, color: Color):
	var side := (to - from).cross(Vector3.UP).normalized() * WIDTH / 2.0
	_quad(from - side, from + side, to + side, to - side, color)


func path(points: PackedVector3Array, color: Color):
	for i in points.size() - 1:
		line(points[i], points[i + 1], color)


# Arrowhead at `to`, pointing from -> to
func arrow(from: Vector3, to: Vector3, color: Color):
	var dir := (to - from).slide(Vector3.UP).normalized() * ARROW_SIZE
	var side := dir.cross(Vector3.UP) * 0.6
	_tri(to + dir * 0.5, to - dir * 0.5 + side, to - dir * 0.5 - side, color)


# Square outline; right and forward are unit directions
func square(center: Vector3, right: Vector3, forward: Vector3, half_size: float, color: Color):
	var corners: Array[Vector3] = []
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		corners.append(center + (right * corner.x + forward * corner.y) * half_size)
	for i in 4:
		line(corners[i], corners[(i + 1) % 4], color)


func marker(pos: Vector3, color: Color):
	var x := Vector3.RIGHT * MARKER_RADIUS
	var z := Vector3.BACK * MARKER_RADIUS
	_quad(pos - x, pos - z, pos + x, pos + z, color)


func write_to(mesh: ArrayMesh):
	mesh.clear_surfaces()
	if _verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_COLOR] = _colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color):
	_tri(a, b, c, color)
	_tri(a, c, d, color)


func _tri(a: Vector3, b: Vector3, c: Vector3, color: Color):
	_verts.append_array([a, b, c])
	_colors.append_array([color, color, color])
