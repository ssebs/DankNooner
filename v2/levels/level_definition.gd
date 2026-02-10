@tool
## All Level objects should inherit from this
## levels are defined in level_manager.gd
class_name LevelDefinition extends Node

@export var level_manager: LevelManager
## Hack - for ui background levels where the player doesn't need to spawn
@export var no_player_spawn_needed: bool
@export var player_entity_scene: PackedScene
@export var player_spawn_pos: Marker3D


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if no_player_spawn_needed:
		return issues

	if level_manager == null:
		issues.append("level_manager must not be empty")
	if player_entity_scene == null:
		issues.append("player_entity_scene must not be empty")
	if player_spawn_pos == null:
		issues.append("player_spawn_pos must not be empty")

	return issues
