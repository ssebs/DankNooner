@tool
## Meshes that you want to change the skin color should use this script
class_name SkinColor extends Node3D

@export var primary_color: Color

## should be a shader texture, see characters/shaders/skin_color.tres
@export var primary_shader_material: ShaderMaterial

@export var primary_mesh: MeshInstance3D

var primary_material: ShaderMaterial


func _ready():
	primary_material = primary_shader_material.duplicate()
	primary_mesh.set_surface_override_material(0, primary_material)
	update_primary_color(primary_color)


func update_primary_color(color: Color):
	primary_color = color
	primary_material.set_shader_parameter("replacement_color", Vector3(color.r, color.g, color.b))


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if primary_mesh == null:
		issues.append("primary_mesh must not be empty")
	if primary_shader_material == null:
		issues.append("primary_shader_material must not be empty")
	if primary_color == null:
		issues.append("primary_color must not be empty")

	return issues
