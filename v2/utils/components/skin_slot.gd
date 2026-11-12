@tool
## A single skin color slot configuration for use with SkinColor.
## Pure data spec — SkinColor owns the runtime material list so the same SkinSlot can drive
## multiple meshes (when referenced more than once in SkinColor.slots).
class_name SkinSlot extends Resource

## Localization key for the garage color row; empty shows "Color N"
@export var display_name: String = ""
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


## A glow slot: its standard_material has emission on, so color drives albedo + emission.
func is_glow() -> bool:
	return use_standard_material and standard_material.emission_enabled


## Apply `new_color` to a runtime material previously produced by make_runtime_material().
## Glow slots take HDR colors (the garage picker's intensity): the overbright part scales the
## authored emission_energy_multiplier, the rest is the hue.
func apply_color_to(runtime_material: Material, new_color: Color) -> void:
	if runtime_material == null:
		return
	if is_glow():
		var mat := runtime_material as StandardMaterial3D
		var intensity := maxf(1.0, maxf(new_color.r, maxf(new_color.g, new_color.b)))
		var hue := Color(new_color.r / intensity, new_color.g / intensity, new_color.b / intensity)
		mat.albedo_color = hue
		mat.emission = hue
		mat.emission_energy_multiplier = standard_material.emission_energy_multiplier * intensity
	elif use_standard_material:
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
