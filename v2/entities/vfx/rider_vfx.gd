@tool
## Rider VFX that IK anims fire through method-track keys. Tracks find this node by name, so an anim
## authored on PlayerEntity fires the same effects on a RiderVisual (garage, NPCs).
class_name RiderVFX extends Node

@export var left_sparks: GPUParticles3D
@export var right_sparks: GPUParticles3D


func set_sparks(on: bool) -> void:
	left_sparks.emitting = on
	right_sparks.emitting = on


## Method keys don't rewind, so a crash or reset mid-anim turns everything off here.
func stop_all() -> void:
	set_sparks(false)


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	if left_sparks == null:
		issues.append("left_sparks must be set")
	if right_sparks == null:
		issues.append("right_sparks must be set")
	return issues
