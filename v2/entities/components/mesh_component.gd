@tool
## Attach to a Node3D & set the export vars to render a mesh
## mesh_definition should be set in code, mesh_node should be set in editor
class_name MeshComponent extends Node3D

@export var mesh_definition: MeshDefinition

@export var mesh_node: Node3D


func _ready():
	_init_mesh()


func _init_mesh():
	for child in mesh_node.get_children():
		child.queue_free()

	var mesh = mesh_definition.mesh_scene.instantiate()
	mesh_node.add_child(mesh)
	mesh.position += mesh_definition.mesh_position_offset
	mesh.rotation_degrees += mesh_definition.mesh_rotation_offset_degrees
	mesh.scale *= mesh_definition.mesh_scale_multiplier
