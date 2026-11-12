@tool
## Arrow strips along the curve, built once into a mesh (a CSG sweep re-evaluates, and costs too
## much over a whole track): a + in cross-section, a flat chevron strip crossed by an upright one of
## the same size so it reads from low angles too. Rebuilt whenever the curve changes. semantic_color fades it, glow too.
class_name RacingLine extends Path3D

@export var semantic_color := SemanticColors.Value.OK:
	set(v):
		semantic_color = v
		if not is_node_ready():
			return
		if Engine.is_editor_hint():
			apply_color(SemanticColors.COLOR_VALUES[v])
		else:
			_from_color = _material().albedo_color
			_elapsed = 0.0

const TRANSITION_DURATION := 0.5
## Metres between cross-sections, each strip's width (the + is WIDTH across and WIDTH tall), and
## how high its bottom floats over the curve.
const STEP := 1.0
const WIDTH := 0.5
const LIFT := -.8

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
	_material().emission = color


func _material() -> StandardMaterial3D:
	return mesh_instance.material_override as StandardMaterial3D


func _build_mesh() -> void:
	var length := curve.get_baked_length()
	var ats := PackedFloat32Array()
	var centres := PackedVector3Array()
	var rights := PackedVector3Array()
	for i in int(length / STEP) + 2:
		var at := minf(i * STEP, length)
		var forward := curve.sample_baked(minf(at + 0.5, length)) - curve.sample_baked(maxf(at - 0.5, 0.0))
		forward.y = 0.0
		ats.append(at)
		centres.append(curve.sample_baked(at) + Vector3.UP * (LIFT + WIDTH * 0.5))
		rights.append(forward.normalized().cross(Vector3.UP))
	var half := WIDTH * 0.5
	var mesh := ArrayMesh.new()
	_add_strip(mesh, ats, centres, rights, Vector2(-half, 0.0), Vector2(half, 0.0))
	_add_strip(mesh, ats, centres, rights, Vector2(0.0, -half), Vector2(0.0, half))
	mesh_instance.mesh = mesh


## One triangle strip along the cross-sections, between edges a and b (x = metres right of the
## centre, y = metres up). u runs along the curve so the arrows point the way it goes, one texture
## tile per WIDTH so both strips show the same single row of chevrons, in step.
func _add_strip(
	mesh: ArrayMesh,
	ats: PackedFloat32Array,
	centres: PackedVector3Array,
	rights: PackedVector3Array,
	a: Vector2,
	b: Vector2
) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in centres.size():
		var right := rights[i]
		# Flat lanes face up, the fin faces sideways
		var normal := Vector3.UP if is_zero_approx(b.y - a.y) else right
		var u := ats[i] / WIDTH
		verts.append(centres[i] + right * a.x + Vector3.UP * a.y)
		verts.append(centres[i] + right * b.x + Vector3.UP * b.y)
		normals.append(normal)
		normals.append(normal)
		uvs.append(Vector2(u, 0.0))
		uvs.append(Vector2(u, 1.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
