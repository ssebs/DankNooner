@tool
## Path-walking animal prop. Mesh, hit volume and speed all come out of an
## AnimalSkinDefinition, the same way PlayerEntity builds itself from a BikeSkinDefinition.
##
## Area3D, not a body: a racer rides straight THROUGH an animal — it dies, they keep going —
## so there is nothing to collide with and the shape is a hit volume rather than a collider.
##
## Motion comes from the PathFollow3D parent AnimalSpawnManager spawns us under. Every peer
## advances it locally at the same speed along the same level-authored curve, so the walk
## itself costs no bandwidth; only the events (spawn, kill, respawn, despawn) cross the wire.
class_name NPCAnimalEntity extends Area3D

## A racer rode through us. Server-only (see _on_body_entered) — AnimalSpawnManager
## broadcasts the kill, so no peer ever decides it locally.
signal hit_by_racer(hitter: Node3D)

@export var animal_skin_definition: AnimalSkinDefinition:
	set(value):
		animal_skin_definition = value
		if Engine.is_editor_hint() and is_node_ready():
			_init_mesh()
			_init_collision_shape()

## Clip names on the glb's own AnimationPlayer. Consts, not per-definition exports: the
## Animated Animal Pack ships one identical clip set for every animal in it.
const WALK_ANIM: String = "Walk"
const DEATH_ANIM: String = "Death"

@onready var spawn_node: Node3D = %Mesh
@onready var collision_shape_3d: CollisionShape3D = $CollisionShape3D

## Set by AnimalSpawnManager before add_child — the parent carrying us along the level's
## Path3D. Only _physics_process touches it, so it is safe to assign either side of _ready.
var path_follow: PathFollow3D
## Instantiated from the definition's mesh_res.
var mesh_skin: SkinColor
## The glb's own AnimationPlayer, riding along inside mesh_skin.
var mesh_anim_player: AnimationPlayer
## Set by AnimalSpawnManager on every peer to start/stop the walk. Cleared on death.
var walking: bool = false
var is_dead: bool = false


func _ready() -> void:
	_init_mesh()
	_init_collision_shape()

	if Engine.is_editor_hint():
		return

	body_entered.connect(_on_body_entered)
	mesh_anim_player.play(WALK_ANIM)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or !walking:
		return
	# Deliberately unsynced — same curve, same speed, same tick rate on every peer. A dead
	# reckoned walk that drifts a few centimetres is not worth a packet per animal per tick.
	path_follow.progress += animal_skin_definition.move_speed * delta


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
	# glb clips import with looping off, so the walk would play once and freeze mid-stride.
	# Only the walk gets flipped: death is meant to play out and hold its last frame.
	mesh_anim_player.get_animation(WALK_ANIM).loop_mode = Animation.LOOP_LINEAR

	if Engine.is_editor_hint():
		mesh_skin.owner = self


## Hit volume from the definition — the same four lines as
## PlayerEntity._init_collision_shape().
func _init_collision_shape() -> void:
	collision_shape_3d.shape = animal_skin_definition.collision_shape
	collision_shape_3d.position = animal_skin_definition.collision_position_offset
	collision_shape_3d.rotation_degrees = animal_skin_definition.collision_rotation_offset_degrees
	collision_shape_3d.scale = animal_skin_definition.collision_scale_multiplier


#endregion

#region public api (driven by AnimalSpawnManager)


## Ridden through by a racer. Cosmetic only — the hit volume goes quiet and the corpse
## holds its last frame until the manager respawns or despawns it.
func die() -> void:
	is_dead = true
	walking = false
	# Deferred: we are inside the physics query that reported the overlap.
	set_deferred("monitoring", false)
	mesh_anim_player.play(DEATH_ANIM)


## Back on its feet, somewhere else along the same path.
func respawn(progress_ratio: float) -> void:
	is_dead = false
	path_follow.progress_ratio = progress_ratio
	set_deferred("monitoring", true)
	mesh_anim_player.play(WALK_ANIM)
	walking = true


#endregion


## The mask already narrows this to crash_collision bodies; the group check rules out
## level obstacles that share that layer. Server-only — clients play back the broadcast.
func _on_body_entered(body: Node3D) -> void:
	if is_dead or multiplayer.multiplayer_peer == null or !multiplayer.is_server():
		return
	if !body.is_in_group(UtilsConstants.GROUPS["Racers"]):
		return
	hit_by_racer.emit(body)


func _get_configuration_warnings() -> PackedStringArray:
	var issues := PackedStringArray()
	if animal_skin_definition == null:
		issues.append("animal_skin_definition must not be empty")
	return issues
