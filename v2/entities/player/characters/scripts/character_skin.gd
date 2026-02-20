@tool
class_name CharacterSkin extends Node3D

@export var mesh_res: Mesh = preload("res://entities/player/characters/assets/biker/biker_mesh.res")

@onready var anim_player: AnimationPlayer = %AnimationPlayer
@onready var mesh_instance: MeshInstance3D = %MeshInstance3D
@onready var skel: Skeleton3D = %Skeleton
