@tool
class_name HUDController extends Control

@export var player_entity: PlayerEntity


## Called from player_entity.gd's do_respawn
func do_reset():
	pass


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if player_entity == null:
		issues.append("player_entity must not be empty")
	return issues
