@tool
## An arrow strip along the curve, built once into a mesh (a CSG sweep re-evaluates, and costs too
## much over a whole track). Rebuilt whenever the curve changes. semantic_color fades the strip.
class_name RacingLine extends Path3D

@export var semantic_color := SemanticColors.Value.OK:
	set(v):
		# Set every frame by a speed readout; an unchanged value must not restart the fade
		if v == semantic_color:
			return
		semantic_color = v
		if not is_node_ready():
			return
		if Engine.is_editor_hint():
			apply_color(SemanticColors.COLOR_VALUES[v])
		else:
			_from_color = _material().albedo_color
			_elapsed = 0.0

const TRANSITION_DURATION := 0.5
## Metres between the strip's cross-sections, its width, how high it floats over the curve, and
## the length of one arrow.
const STEP := 1.0
const WIDTH := 1.0
const LIFT := 0.15
const ARROW_LENGTH := 2.0

@onready var mesh_instance: MeshInstance3D = %Mesh

var _from_color := Color.WHITE
var _elapsed := TRANSITION_DURATION


func _ready():
	apply_color(SemanticColors.COLOR_VALUES[semantic_color])
	_build_mesh()
	curve_changed.connect(_build_mesh)


func _process(delta: float):
	if _elapsed >= TRANSITION_DURATION:
		return
	_elapsed = minf(_elapsed + delta, TRANSITION_DURATION)
	var t := _elapsed / TRANSITION_DURATION
	apply_color(_from_color.lerp(SemanticColors.COLOR_VALUES[semantic_color], t))


func apply_color(color: Color):
	_material().albedo_color = color


func _material() -> StandardMaterial3D:
	return mesh_instance.material_override as StandardMaterial3D


## A flat triangle strip centred on the curve, u running along it so the arrows point the way it goes.
func _build_mesh() -> void:
	var length := curve.get_baked_length()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in int(length / STEP) + 2:
		var at := minf(i * STEP, length)
		var forward := curve.sample_baked(minf(at + 0.5, length)) - curve.sample_baked(maxf(at - 0.5, 0.0))
		forward.y = 0.0
		var half := forward.normalized().cross(Vector3.UP) * WIDTH * 0.5
		var p := curve.sample_baked(at) + Vector3.UP * LIFT
		var u := at / ARROW_LENGTH
		verts.append(p - half)
		verts.append(p + half)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		uvs.append(Vector2(u, 0.0))
		uvs.append(Vector2(u, 1.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
	mesh_instance.mesh = mesh
