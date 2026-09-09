@tool
extends Node3D
## HACK
@export var del_end_ramp: bool = false

@onready var end_ramp = %EndRamp

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	
	if del_end_ramp:
		end_ramp.queue_free()
