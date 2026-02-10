@tool
extends LevelDefinition

var player: PlayerEntity


func _ready():
	pass
	# TODO: if singleplayer, run spawn_player()


func spawn_player() -> PlayerEntity:
	player = player_entity_scene.instantiate()
	player_spawn_pos.add_child(player)
	return player
