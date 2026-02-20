@tool
class_name CharacterSkin extends Node3D

@export
var mesh_res: PackedScene = preload("res://entities/player/characters/assets/clanker/Clanker.glb")

# @export var scale

@onready var anim_player: AnimationPlayer = %AnimationPlayer
@onready var mesh_node: Node3D = %MeshNode


func _ready():
	spawn_mesh()


func spawn_mesh():
	for child in mesh_node.get_children():
		child.queue_free()
	var m = mesh_res.instantiate()
	mesh_node.add_child(m)

	# retarget AnimationMixer => Root Node to new mesh
	anim_player.root_node = m.get_path()
	anim_player.play("Biker/reset")
