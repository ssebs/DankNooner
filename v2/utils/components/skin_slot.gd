@tool
## A single skin color slot configuration for use with SkinColor
class_name SkinSlot extends Resource

## The color to apply to this slot
@export var color: Color = Color.WHITE
## Use StandardMaterial3D instead of ShaderMaterial
@export var use_standard_material: bool = false
## Which surface index to override on the mesh
@export var surface_index: int = 0
## Used when use_standard_material is true
@export var standard_material: StandardMaterial3D
## Used when use_standard_material is false (e.g. characters/shaders/skin_color.tres)
@export var shader_material: ShaderMaterial

## Runtime reference to the mesh (set by SkinColor via setup())
var mesh: MeshInstance3D
## Runtime duplicate of the material (set by SkinColor)
var runtime_material: Material


func setup(target_mesh: MeshInstance3D) -> void:
	mesh = target_mesh
	if use_standard_material:
		runtime_material = standard_material.duplicate()
	else:
		runtime_material = shader_material.duplicate()
	mesh.set_surface_override_material(surface_index, runtime_material)
	update_color(color)


func update_color(new_color: Color) -> void:
	color = new_color
	if runtime_material == null:
		return
	if use_standard_material:
		(runtime_material as StandardMaterial3D).albedo_color = new_color
	else:
		runtime_material.set_shader_parameter(
			"replacement_color", Vector3(new_color.r, new_color.g, new_color.b)
		)


func get_configuration_issues() -> PackedStringArray:
	var issues: PackedStringArray = []
	if use_standard_material:
		if standard_material == null:
			issues.append("standard_material required when use_standard_material is true")
	else:
		if shader_material == null:
			issues.append("shader_material required when use_standard_material is false")
	return issues
