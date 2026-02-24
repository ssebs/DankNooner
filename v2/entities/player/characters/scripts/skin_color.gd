@tool
## Meshes that you want to change the skin color should use this script
class_name SkinColor extends Node3D

@export_group("Primary")
@export var primary_color: Color
## Use StandardMaterial3D instead of shader material (for multi-material meshes)
@export var primary_use_standard_material: bool = false
## Which surface index to override. Meshes can have multiple materials; this targets a specific one.
@export var primary_surface_index: int = 0
## Used when primary_use_standard_material is true
@export var primary_standard_material: StandardMaterial3D
## Used when primary_use_standard_material is false (see characters/shaders/skin_color.tres)
@export var primary_shader_material: ShaderMaterial
@export var primary_mesh: MeshInstance3D

@export_group("Secondary")
@export var has_secondary: bool = false
@export var secondary_color: Color
@export var secondary_use_standard_material: bool = false
## Which surface index to override. Meshes can have multiple materials; this targets a specific one.
@export var secondary_surface_index: int = 0
@export var secondary_standard_material: StandardMaterial3D
@export var secondary_shader_material: ShaderMaterial
@export var secondary_mesh: MeshInstance3D

var primary_material: Material
var secondary_material: Material


func _ready():
	if primary_use_standard_material:
		primary_material = primary_standard_material.duplicate()
	else:
		primary_material = primary_shader_material.duplicate()
	primary_mesh.set_surface_override_material(primary_surface_index, primary_material)
	update_primary_color(primary_color)

	if has_secondary:
		if secondary_use_standard_material:
			secondary_material = secondary_standard_material.duplicate()
		else:
			secondary_material = secondary_shader_material.duplicate()
		secondary_mesh.set_surface_override_material(secondary_surface_index, secondary_material)
		update_secondary_color(secondary_color)


func update_primary_color(color: Color):
	primary_color = color
	if primary_use_standard_material:
		(primary_material as StandardMaterial3D).albedo_color = color
	else:
		primary_material.set_shader_parameter(
			"replacement_color", Vector3(color.r, color.g, color.b)
		)


func update_secondary_color(color: Color):
	secondary_color = color
	if secondary_use_standard_material:
		(secondary_material as StandardMaterial3D).albedo_color = color
	else:
		secondary_material.set_shader_parameter(
			"replacement_color", Vector3(color.r, color.g, color.b)
		)


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if primary_mesh == null:
		issues.append("primary_mesh must not be empty")
	if primary_use_standard_material:
		if primary_standard_material == null:
			issues.append("primary_standard_material must not be empty")
	else:
		if primary_shader_material == null:
			issues.append("primary_shader_material must not be empty")

	if has_secondary:
		if secondary_mesh == null:
			issues.append("secondary_mesh must not be empty")
		if secondary_use_standard_material:
			if secondary_standard_material == null:
				issues.append("secondary_standard_material must not be empty")
		else:
			if secondary_shader_material == null:
				issues.append("secondary_shader_material must not be empty")

	return issues
