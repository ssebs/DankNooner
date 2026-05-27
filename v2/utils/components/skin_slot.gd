@tool
## A single skin color slot configuration for use with SkinColor.
## Pure data spec — SkinColor owns the runtime material list so the same SkinSlot can drive
## multiple meshes (when referenced more than once in SkinColor.slots).
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


## Create a fresh runtime material from this slot's spec. SkinColor calls this per
## (slot-position, mesh) pair so each mesh gets its own material instance.
func make_runtime_material() -> Material:
	if use_standard_material:
		return standard_material.duplicate() if standard_material else null
	return shader_material.duplicate() if shader_material else null


## Apply `new_color` to a runtime material previously produced by make_runtime_material().
func apply_color_to(runtime_material: Material, new_color: Color) -> void:
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
