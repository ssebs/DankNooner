@tool
class_name EntityMesh extends Node3D

@export var mesh_scene: PackedScene

@export_group("Mesh Transform")
@export var mesh_position: Vector3 = Vector3.ZERO
@export var mesh_rotation_degrees: Vector3 = Vector3.ZERO
@export var mesh_scale: Vector3 = Vector3.ONE

var mesh: Node3D


func _ready():
	load_mesh()


func load_mesh():
	for child in get_children():
		child.queue_free()

	mesh = mesh_scene.instantiate()
	mesh.position = mesh_position
	mesh.rotation_degrees = mesh_rotation_degrees
	mesh.scale = mesh_scale
	add_child(mesh)


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if mesh_scene == null:
		issues.append("mesh_scene must not be empty")

	return issues
