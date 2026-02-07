@tool
## All Bike objects should be defined from this
class_name BikeDefinition extends Resource

@export_group("Bike Mesh")
@export var mesh_scene: PackedScene
@export var mesh_position_offset: Vector3 = Vector3.ZERO
@export var mesh_rotation_offset_degrees: Vector3 = Vector3.ZERO
@export var mesh_scale_multiplier: Vector3 = Vector3.ONE

@export_group("Bike Collision")
@export var collision_shape: Shape3D
@export var collision_position_offset: Vector3 = Vector3.ZERO
@export var collision_rotation_offset_degrees: Vector3 = Vector3.ZERO
@export var collision_scale_multiplier: Vector3 = Vector3.ONE

# TBD:
# @export var color_override: Color
# @export var mods: Array[BikeMod]

# transforms...
# player_entity.gd should use this to set vals from
