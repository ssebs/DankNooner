@tool
## Drop into any scene to light up the edges of every mesh under this node's parent
## (including instanced .glb meshes and ones spawned later). One shared overlay material per NeonEdges node.
class_name NeonEdges extends Node

@export var color: Color = Color("41afff"):
	set(v):
		color = v
		_apply_params()

@export_range(0.0, 16.0) var energy: float = 4.0:
	set(v):
		energy = v
		_apply_params()

@export_range(0.5, 8.0) var width_px: float = 1.5:
	set(v):
		width_px = v
		_apply_params()

@export_range(0.0, 1.0) var depth_threshold: float = 0.05:
	set(v):
		depth_threshold = v
		_apply_params()

@export_range(0.0, 2.0) var normal_threshold: float = 0.4:
	set(v):
		normal_threshold = v
		_apply_params()

const SCREEN_NEON_EDGES_SHADER := preload("res://levels/components/screen_neon_edges.gdshader")

var _mat := ShaderMaterial.new()


func _init():
	_mat.shader = SCREEN_NEON_EDGES_SHADER


func _enter_tree():
	get_tree().node_added.connect(_on_node_added)


func _exit_tree():
	get_tree().node_added.disconnect(_on_node_added)


func _ready():
	_apply_params()
	for mesh: MeshInstance3D in get_parent().find_children("*", "MeshInstance3D", true, false):
		mesh.material_overlay = _mat


# Catches meshes spawned after _ready, e.g. PlayerEntity rebuilding its skins after a crash.
func _on_node_added(node: Node):
	if node is MeshInstance3D and get_parent().is_ancestor_of(node):
		node.material_overlay = _mat


func _apply_params():
	_mat.set_shader_parameter("edge_color", color)
	_mat.set_shader_parameter("edge_energy", energy)
	_mat.set_shader_parameter("edge_width_px", width_px)
	_mat.set_shader_parameter("depth_threshold", depth_threshold)
	_mat.set_shader_parameter("normal_threshold", normal_threshold)
