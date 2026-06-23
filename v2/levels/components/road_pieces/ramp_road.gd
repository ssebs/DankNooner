@tool
class_name RampRoad extends Node3D

## matches the idx of meshes
@export var variation: int = 1:
	set(value):
		variation = value
		# if is_node_ready():
		# 	_apply_variation()
## idx must match int in variation
@export var meshes: Dictionary[int, ArrayMesh]

## Mesh surface material name -> collision_layer bitmask for that surface.
@export var material_layers: Dictionary[StringName, int]:
	set(value):
		material_layers = value
		update_configuration_warnings()
		# if is_node_ready():
		# 	_rebuild_collisions()

const GENERATED_COL_PREFIX: String = "SurfaceCol_"

@onready var mesh: MeshInstance3D = %Mesh
