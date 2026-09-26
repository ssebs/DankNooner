@tool
class_name GrayBoxStaticBody extends StaticBody3D

enum ShapeMode { BOX, PLANE }

@export var shape_mode: ShapeMode = ShapeMode.BOX:
	set(v):
		shape_mode = v
		rebuild_geometry()

@export var width: float = 2.0:
	set(v):
		width = v
		apply_shape()

@export var height: float = 2.0:
	set(v):
		height = v
		apply_shape()

@export var depth: float = 2.0:
	set(v):
		depth = v
		apply_shape()

@export var color_preset: MaterialPresets.Preset = MaterialPresets.Preset.DARK_GRAY:
	set(v):
		color_preset = v
		apply_color()

# When set, this material is used as-is and the color_preset system is skipped.
@export var material_override: Material:
	set(v):
		material_override = v
		apply_color()

@export var neon_edges: bool = false:
	set(v):
		neon_edges = v
		apply_neon_edges()

@export var neon_color: Color = Color("41afff"):
	set(v):
		neon_color = v
		apply_neon_edges()

const NEON_EDGES_SHADER := preload("res://levels/assets/graybox/neon_edges.gdshader")

# PlaneMesh has no finite collision shape, so PLANE mode uses a thin BoxShape3D
# spanning width x depth. height is ignored in PLANE mode.
const PLANE_COLLISION_THICKNESS: float = 0.05

static var _mesh_cache: Dictionary = {}
static var _neon_material: ShaderMaterial

@onready var meshinstance: MeshInstance3D = %MeshInstance3D
@onready var collisionshape: CollisionShape3D = %CollisionShape3D


func _ready():
	rebuild_geometry()
	apply_color()


# Gives this body its own collision shape, then sizes it and picks the shared mesh.
func rebuild_geometry():
	if not is_node_ready():
		return

	collisionshape.shape = BoxShape3D.new()
	apply_shape()


func apply_shape():
	if not is_node_ready():
		return

	match shape_mode:
		ShapeMode.BOX:
			meshinstance.mesh = _get_shared_mesh(Vector3(width, height, depth))
			collisionshape.shape.size = Vector3(width, height, depth)
		ShapeMode.PLANE:
			meshinstance.mesh = _get_shared_mesh(Vector3(width, 0.0, depth))
			collisionshape.shape.size = Vector3(width, PLANE_COLLISION_THICKNESS, depth)

	apply_neon_edges()


# y = 0 keys a PlaneMesh. Shared so same-sized boxes can be auto-instanced — never mutate
static func _get_shared_mesh(size: Vector3) -> PrimitiveMesh:
	if _mesh_cache.has(size):
		return _mesh_cache[size]
	var mesh: PrimitiveMesh
	if size.y == 0.0:
		mesh = PlaneMesh.new()
		mesh.size = Vector2(size.x, size.z)
	else:
		mesh = BoxMesh.new()
		mesh.size = size
	_mesh_cache[size] = mesh
	return mesh


func apply_color():
	if not is_node_ready():
		return

	if material_override != null:
		meshinstance.set_surface_override_material(0, material_override)
		return

	# Reuse the .tscn override material's texture (kenney texture_04) so the
	# triplanar look is preserved; MaterialPresets rebuilds it with the tint.
	var existing := meshinstance.get_surface_override_material(0) as StandardMaterial3D
	var texture: Texture2D = existing.albedo_texture if existing else null
	meshinstance.set_surface_override_material(0, MaterialPresets.make_material(color_preset, texture))


# Overlay pass, so it layers on top of either color_preset or material_override.
func apply_neon_edges():
	if not is_node_ready():
		return

	if not neon_edges:
		meshinstance.material_overlay = null
		return

	if _neon_material == null:
		_neon_material = ShaderMaterial.new()
		_neon_material.shader = NEON_EDGES_SHADER
	meshinstance.material_overlay = _neon_material
	meshinstance.set_instance_shader_parameter("edge_color", neon_color)
	var mesh_height := height if shape_mode == ShapeMode.BOX else 0.0
	meshinstance.set_instance_shader_parameter("size", Vector3(width, mesh_height, depth))
