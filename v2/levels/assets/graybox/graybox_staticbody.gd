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

# PlaneMesh has no finite collision shape, so PLANE mode uses a thin BoxShape3D
# spanning width x depth. height is ignored in PLANE mode.
const PLANE_COLLISION_THICKNESS: float = 0.05

@onready var meshinstance: MeshInstance3D = %MeshInstance3D
@onready var collisionshape: CollisionShape3D = %CollisionShape3D


func _ready():
	rebuild_geometry()
	apply_color()


# Swaps mesh/shape resources to match shape_mode, then sizes them.
func rebuild_geometry():
	if not is_node_ready():
		return

	match shape_mode:
		ShapeMode.BOX:
			meshinstance.mesh = BoxMesh.new()
			collisionshape.shape = BoxShape3D.new()
		ShapeMode.PLANE:
			meshinstance.mesh = PlaneMesh.new()
			collisionshape.shape = BoxShape3D.new()

	apply_shape()


func apply_shape():
	if not is_node_ready():
		return

	match shape_mode:
		ShapeMode.BOX:
			meshinstance.mesh.size = Vector3(width, height, depth)
			collisionshape.shape.size = Vector3(width, height, depth)
		ShapeMode.PLANE:
			meshinstance.mesh.size = Vector2(width, depth)
			collisionshape.shape.size = Vector3(width, PLANE_COLLISION_THICKNESS, depth)


func apply_color():
	if not is_node_ready():
		return

	# Reuse the .tscn override material's texture (kenney texture_04) so the
	# triplanar look is preserved; MaterialPresets rebuilds it with the tint.
	var existing := meshinstance.get_surface_override_material(0) as StandardMaterial3D
	var texture: Texture2D = existing.albedo_texture if existing else null
	meshinstance.set_surface_override_material(0, MaterialPresets.make_material(color_preset, texture))
