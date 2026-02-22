@tool
class_name SkinColor extends Node3D

@export var primary_color: Color
## should be a shader texture, see characters/shaders/skin_color.tres
@export var primary_shader_material: ShaderMaterial

@export var primary_mesh: MeshInstance3D


func _ready():
	var mat = primary_shader_material.duplicate()
	mat.set_shader_parameter(
		"replacement_color", Vector3(primary_color.r, primary_color.g, primary_color.b)
	)
	primary_mesh.set_surface_override_material(0, mat)


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if primary_mesh == null:
		issues.append("primary_mesh must not be empty")
	if primary_shader_material == null:
		issues.append("primary_shader_material must not be empty")
	if primary_color == null:
		issues.append("primary_color must not be empty")

	return issues
