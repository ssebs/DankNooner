@tool
## All Level objects should inherit from this
## levels are defined in level_manager.gd
class_name LevelDefinition extends Node3D

## Hack - for ui background levels where the player doesn't need to spawn
@export var no_player_spawn_needed: bool
@export var player_entity_scene: PackedScene = preload("res://entities/player/player_entity.tscn")
@export var player_spawn_pos: Marker3D
@export var player_spawn_pos_debug: Marker3D

## Set in level_manager
var level_manager: LevelManager
var level_name: LevelManager.LevelName


func _ready():
	if OS.has_feature("debug"):
		player_spawn_pos = player_spawn_pos_debug


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if no_player_spawn_needed:
		return issues

	if player_entity_scene == null:
		issues.append("player_entity_scene must not be empty")
	if player_spawn_pos == null:
		issues.append("player_spawn_pos must not be empty")

	return issues
