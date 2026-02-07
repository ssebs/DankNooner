@tool
extends LevelDefinition

@export var player_entity_scene: PackedScene
@export var player_spawn_pos: Marker3D

var player: PlayerEntity


func _ready():
	spawn_player()


func spawn_player() -> PlayerEntity:
	player = player_entity_scene.instantiate()
	player_spawn_pos.add_child(player)
	return player


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if player_entity_scene == null:
		issues.append("player_entity_scene must not be empty")
	if player_spawn_pos == null:
		issues.append("player_spawn_pos must not be empty")

	return issues
