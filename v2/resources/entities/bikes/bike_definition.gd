@tool
## All Bike objects should be defined from this
class_name BikeDefinition extends Resource

@export var bike_mesh_definition: MeshDefinition

@export_group("Bike Collision")
@export var collision_shape: Shape3D
@export var collision_position_offset: Vector3 = Vector3.ZERO
@export var collision_rotation_offset_degrees: Vector3 = Vector3.ZERO
@export var collision_scale_multiplier: Vector3 = Vector3.ONE

# TBD:
# @export var color_override: Color
# @export var mods: Array[BikeMod]
# BikeMod is a MeshDefinition with an attachment point Marker3D w/ script

# transforms...
# player_entity.gd should use this to set vals from
