@tool
## Looks + collision for an NPC car. Bike tuning (gearing, lean, tricks, rider pose) has no
## meaning on a car, so this is BikeSkinDefinition's Mesh/Collision/Mods groups and nothing
## else. Traffic-only, so no user:// save/load.
class_name CarSkinDefinition extends Resource

## Name of the skin
@export var skin_name: String = "replace_me"

@export_group("Mesh")
## The SkinColor scene to instantiate
@export var mesh_res: PackedScene:
	set(value):
		if value:
			var instance = value.instantiate()
			assert(instance is SkinColor, "Wrong scene type!")
			instance.free()
		mesh_res = value
@export var mesh_position_offset: Vector3 = Vector3.ZERO
@export var mesh_rotation_offset_degrees: Vector3 = Vector3.ZERO
@export var mesh_scale_multiplier: Vector3 = Vector3.ONE

@export_group("Collision")
@export var collision_shape: Shape3D = preload("res://resources/cars/hitbox/car_hitbox.tres")
@export var collision_position_offset: Vector3 = Vector3(0, 0.75, 0)
@export var collision_rotation_offset_degrees: Vector3 = Vector3.ZERO
@export var collision_scale_multiplier: Vector3 = Vector3.ONE

@export_group("Mods")
@export var mods: Array[BikeMod] = []
