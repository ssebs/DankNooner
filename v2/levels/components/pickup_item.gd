@tool
class_name PickupItem extends Area3D

@export var pickup_item_definition:PickupItemDefinition

@onready var mesh_node:Node3D= %MeshNode
@onready var collishion_shape:CollisionShape3D= %CollisionShape3D
@onready var mesh_instance:MeshInstance3D=%MeshInstance3D

func _ready():
	_apply_definition()
func _apply_definition():
	pass