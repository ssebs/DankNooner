@tool
## Gate / ring that fires `entered` when a PlayerEntity passes through.
## Reused by tutorial checkpoint objectives and by Street Race checkpoints.
class_name CheckPointMarker extends GameModeObject

@export var width: float = 8.0:
	set(value):
		width = value
		_apply_width()
@export var sign_text: String = "REPLACE_ME":
	set(value):
		sign_text = value
		_apply_sign_text()

@onready var _trigger_shape: CollisionShape3D = $Area3D/CollisionShape3D
@onready var _label: Label3D = %Label3D


func _ready():
	super()
	_trigger_shape.shape = BoxShape3D.new()
	_apply_width()
	_apply_sign_text()


func _apply_width():
	if !is_node_ready():
		return
	(_trigger_shape.shape as BoxShape3D).size = Vector3(width, 4, 1)


func _apply_sign_text():
	if !is_node_ready():
		return
	_label.text = sign_text
