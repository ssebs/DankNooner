@tool
## Kinematic animal prop. Mesh and collider both come out of an AnimalSkinDefinition, the
## same way PlayerEntity builds itself from a BikeSkinDefinition — swap the .tres and the
## scene rebuilds in-editor.
##
## AnimatableBody3D (not CharacterBody3D): nothing here simulates. `anim_player` on the
## root animates the body along its path, and sync_to_physics makes it shove whatever it
## walks into; `mesh_anim_player` inside the spawned mesh plays the glb's own clips.
class_name NPCAnimalEntity extends AnimatableBody3D

@export var animal_skin_definition: AnimalSkinDefinition:
	set(value):
		animal_skin_definition = value
		if Engine.is_editor_hint() and is_node_ready():
			_init_mesh()
			_init_collision_shape()

@onready var anim_player: AnimationPlayer = %AnimationPlayer
@onready var spawn_node: Node3D = %Mesh
@onready var collision_shape_3d: CollisionShape3D = $CollisionShape3D

## Instantiated from the definition's mesh_res.
var mesh_skin: SkinColor
## The glb's own AnimationPlayer, riding along inside mesh_skin. Distinct from `anim_player`
## on the root: that one moves the animal, this one makes it walk.
var mesh_anim_player: AnimationPlayer


func _ready() -> void:
	_init_mesh()
	_init_collision_shape()


#region init
## Spawn the definition's mesh under %Mesh — PlayerEntity._init_mesh via CarSkin._spawn_mesh,
## minus the mod pass (animals have no mod ecosystem).
func _init_mesh() -> void:
	for child in spawn_node.get_children():
		child.queue_free()
	mesh_skin = animal_skin_definition.mesh_res.instantiate()
	spawn_node.add_child(mesh_skin)

	mesh_skin.scale *= animal_skin_definition.mesh_scale_multiplier
	mesh_skin.position += animal_skin_definition.mesh_position_offset
	mesh_skin.rotation_degrees += animal_skin_definition.mesh_rotation_offset_degrees

	# Named by the glb importer, so it is there on every animated animal scene. A skin whose
	# mesh_res carries no animations is a mis-authored skin — crash rather than hide it.
	mesh_anim_player = mesh_skin.get_node("AnimationPlayer")

	if Engine.is_editor_hint():
		mesh_skin.owner = self


## Collider from the definition — the same four lines as PlayerEntity._init_collision_shape().
func _init_collision_shape() -> void:
	collision_shape_3d.shape = animal_skin_definition.collision_shape
	collision_shape_3d.position = animal_skin_definition.collision_position_offset
	collision_shape_3d.rotation_degrees = animal_skin_definition.collision_rotation_offset_degrees
	collision_shape_3d.scale = animal_skin_definition.collision_scale_multiplier


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues := PackedStringArray()
	if animal_skin_definition == null:
		issues.append("animal_skin_definition must not be empty")
	return issues
