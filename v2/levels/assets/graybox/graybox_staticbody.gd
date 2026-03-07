@tool
class_name GrayBoxStaticBody extends StaticBody3D

enum GrayBoxColor { DARK_GRAY, LIGHT_GRAY, GREEN, BLUE, RED, PURPLE, TAN }

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

@export var color_preset: GrayBoxColor = GrayBoxColor.DARK_GRAY:
	set(v):
		color_preset = v
		apply_color()

const COLOR_VALUES: Dictionary = {
	GrayBoxColor.DARK_GRAY: Color(1.0, 1.0, 1.0),
	GrayBoxColor.LIGHT_GRAY: Color(2.363, 2.363, 2.363),
	GrayBoxColor.GREEN: Color(0.729, 1.857, 0.365),
	GrayBoxColor.BLUE: Color(0.365, 1.787, 1.857),
	GrayBoxColor.RED: Color(1.975, 0.209, 0.209),
	GrayBoxColor.PURPLE: Color(2.113, 1.029, 2.418),
	GrayBoxColor.TAN: Color(2.807, 2.352, 1.369)
}

@onready var meshinstance: MeshInstance3D = %MeshInstance3D
@onready var collisionshape: CollisionShape3D = %CollisionShape3D


func _ready():
	meshinstance.mesh = BoxMesh.new()
	collisionshape.shape = BoxShape3D.new()
	apply_shape()
	apply_color()


func apply_shape():
	if not is_node_ready():
		return

	meshinstance.mesh.size = Vector3(width, height, depth)
	collisionshape.shape.size = Vector3(width, height, depth)


func apply_color():
	if not is_node_ready():
		return

	var mat := meshinstance.get_surface_override_material(0) as StandardMaterial3D
	if not mat:
		mat = StandardMaterial3D.new()
		meshinstance.set_surface_override_material(0, mat)
	else:
		mat = mat.duplicate()
		meshinstance.set_surface_override_material(0, mat)
	mat.albedo_color = COLOR_VALUES.get(color_preset, Color.WHITE)
