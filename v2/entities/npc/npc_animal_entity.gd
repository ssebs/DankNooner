@tool
## Animal prop, hand-placed in a level. Mesh, hit volume and speed all come out of an
## AnimalSkinDefinition, the same way PlayerEntity builds itself from a BikeSkinDefinition.
##
## **The PARENT decides the behavior.** Under a Path3D we walk that curve; parked anywhere
## else we stand and idle. Drag an animal onto a different Path3D and it walks that one
## instead — no code, no manager wiring. Several animals can share a path: each seeds its
## own offset from wherever you dropped it, so they stay spread out.
##
## Area3D, not a body: a racer rides straight THROUGH an animal — it dies, they keep going —
## so there is nothing to collide with and the shape is a hit volume rather than a collider.
##
## The walk costs no bandwidth. Every peer loads the same level, so it has the same curve,
## the same speed and the same authored start offset, and simply walks it. Only the events
## that peers cannot each decide alone — the kill and the respawn — are broadcast, by
## AnimalSpawnManager.
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
const IDLE_ANIM: String = "Idle"
const DEATH_ANIM: String = "Death"
## Metres ahead on the curve used to pick the facing, so the animal turns INTO a corner
## rather than tracking a frame behind it.
const FACING_LOOKAHEAD: float = 0.5

@onready var spawn_node: Node3D = %Mesh
@onready var collision_shape_3d: CollisionShape3D = $CollisionShape3D

## Our parent, when it is a Path3D. Null means we idle where we were placed.
var path: Path3D
## Instantiated from the definition's mesh_res.
var mesh_skin: SkinColor
## The glb's own AnimationPlayer, riding along inside mesh_skin.
var mesh_anim_player: AnimationPlayer
## Walking the curve. False for idlers and for anything currently dead.
var walking: bool = false
var is_dead: bool = false

## Distance along the curve, in metres.
var _progress: float = 0.0


func _ready() -> void:
	# An animal you just dropped into a level legitimately has no definition yet —
	# _get_configuration_warnings is what nags you about that. At runtime it IS a bug, so
	# fall through and let the null deref below say so.
	if Engine.is_editor_hint() and animal_skin_definition == null:
		return

	_init_mesh()
	_init_collision_shape()

	if Engine.is_editor_hint():
		return

	body_entered.connect(_on_body_entered)

	path = get_parent() as Path3D
	if path == null:
		mesh_anim_player.play(IDLE_ANIM)
		return
	# Seed from where the author dropped us, so a herd sharing one path starts spread along
	# it instead of stacking on its origin. Also what keeps every peer in step: the authored
	# position is in the level scene, so they all derive the same offset with nothing synced.
	_progress = path.curve.get_closest_offset(position)
	mesh_anim_player.play(WALK_ANIM)
	walking = true


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or !walking:
		return
	var length := path.curve.get_baked_length()
	_progress = fmod(_progress + animal_skin_definition.move_speed * delta, length)

	# Curve space IS our parent's local space, so these go straight into position/rotation.
	var here := path.curve.sample_baked(_progress)
	var heading := path.curve.sample_baked(fmod(_progress + FACING_LOOKAHEAD, length)) - here
	position = here
	heading.y = 0.0
	if heading.length_squared() > 0.0001:
		# Yaw only, matching NPCRiderEntity._face_velocity — our front is -Z (see _init_mesh),
		# and letting the curve's tilt through would roll the animal onto its side.
		rotation.y = atan2(-heading.x, -heading.z)


#region init
## Spawn the definition's mesh under %Mesh — PlayerEntity._init_mesh via CarSkin._spawn_mesh,
## minus the mod pass (animals have no mod ecosystem).
##
## %Mesh is yawed 180° in the scene, matching PlayerEntity's VisualRoot: the pack's glbs are
## Blender exports and face +Z, while we walk the curve facing -Z, so without it every
## animal moonwalks. Two consequences for the definition's offsets:
## mesh_position_offset is applied in that yawed space (its X and Z read mirrored), and an
## animal that already faces -Z cancels the yaw with mesh_rotation_offset_degrees = (0,180,0).
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
	# Death is left alone on purpose — it is meant to play out and hold its last frame.
	mesh_anim_player.get_animation(WALK_ANIM).loop_mode = Animation.LOOP_LINEAR
	mesh_anim_player.get_animation(IDLE_ANIM).loop_mode = Animation.LOOP_LINEAR


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


## Back on its feet where it went down, and walking on from there.
func respawn() -> void:
	is_dead = false
	set_deferred("monitoring", true)
	if path == null:
		mesh_anim_player.play(IDLE_ANIM)
		return
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
