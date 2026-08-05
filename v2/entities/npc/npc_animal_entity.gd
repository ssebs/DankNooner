@tool
class_name NPCAnimalEntity extends AnimatableBody3D

@export var animal_skin_definition: AnimalSkinDefinition

@onready var anim_player: AnimationPlayer = %AnimationPlayer
@onready var spawn_node: Node3D = %Mesh
