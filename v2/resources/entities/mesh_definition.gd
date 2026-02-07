@tool
## All mesh objects should be defined from this
class_name MeshDefinition extends Resource

@export var mesh_scene: PackedScene
@export var mesh_position_offset: Vector3 = Vector3.ZERO
@export var mesh_rotation_offset_degrees: Vector3 = Vector3.ZERO
@export var mesh_scale_multiplier: Vector3 = Vector3.ONE
