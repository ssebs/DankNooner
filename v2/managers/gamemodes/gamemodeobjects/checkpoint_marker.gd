@tool
## Gate / ring that fires `entered` when a PlayerEntity passes through.
## Reused by tutorial checkpoint objectives and by Street Race checkpoints.
class_name CheckPointMarker extends GameModeObject

@export var width: float = 16.0:
	set(value):
		width = value
		_apply_width()

@onready var _trigger_shape: CollisionShape3D = %CollisionShape3D
@onready var _border_left: Node3D = %BorderCylLeft
@onready var _border_right: Node3D = %BorderCylRight


func _ready():
	super()
	_trigger_shape.shape = BoxShape3D.new()
	_apply_width()


func _apply_width():
	if !is_node_ready():
		return
	(_trigger_shape.shape as BoxShape3D).size = Vector3(width, 64, 1)
	_border_left.position.x = - width / 2.0
	_border_right.position.x = width / 2.0
