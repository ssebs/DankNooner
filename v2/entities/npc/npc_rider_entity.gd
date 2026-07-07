## Kinematic AI race rider — it just moves and collides. No netfox rollback,
## no input simulation, no bike physics. The server simulates (NPCRaceManager
## sets nav targets and owns crash/respawn timers); clients are passive and
## receive `transform` + `npc_state` via the child MultiplayerSynchronizer.
##
## Bike front is VisualRoot-local +Z (VisualRoot is identity here, unlike the
## player's 180°-yawed one), so steering yaws the body to face velocity with +Z.
class_name NPCRiderEntity extends CharacterBody3D

enum NPCState { RIDING, WHEELIE, CRASHED, FINISHED }

@export var bike_definition: BikeSkinDefinition
@export var character_definition: CharacterSkinDefinition
@export var animation_controller: NPCAnimationController
@export var move_speed: float = 22.0
@export var turn_speed: float = 4.0

const GRAVITY: float = 30.0
## Checkpoints are static — only retarget when the target actually moved,
## since set_target_position triggers an expensive A* search.
const RETARGET_DISTANCE_SQ: float = 1.0

@onready var nav_agent: NavigationAgent3D = %NavigationAgent3D
@onready var visual_root: Node3D = %VisualRoot
@onready var bike_skin: BikeSkin = %BikeSkin
@onready var character_skin: CharacterSkin = %CharacterSkin
@onready var name_label: Label3D = %NameLabel

## Synced to clients via MultiplayerSynchronizer (server authority).
var npc_state: NPCState = NPCState.RIDING

var username: String:
	set(v):
		username = v
		if is_node_ready():
			name_label.text = username

var _has_target: bool = false
var _last_target_pos: Vector3 = Vector3.INF


func _ready():
	bike_skin.skin_definition = bike_definition
	bike_skin._apply_definition()
	character_skin.skin_definition = character_definition
	character_skin.apply_definition()
	animation_controller.initialize()
	name_label.text = username

	add_to_group(UtilsConstants.GROUPS["Racers"])
	set_multiplayer_authority(1)
	nav_agent.velocity_computed.connect(_on_velocity_computed)


func _physics_process(delta: float):
	if !multiplayer.is_server():
		return

	var driving := (
		_has_target
		and npc_state != NPCState.CRASHED
		and npc_state != NPCState.FINISHED
		and !nav_agent.is_navigation_finished()
	)
	if driving:
		var next_pos := nav_agent.get_next_path_position()
		var dir := (next_pos - global_position).normalized()
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed * delta)
		velocity.z = move_toward(velocity.z, 0.0, move_speed * delta)

	velocity.y -= GRAVITY * delta

	if nav_agent.avoidance_enabled:
		nav_agent.set_velocity(velocity)
	else:
		_on_velocity_computed(velocity)

	_face_velocity(delta)


#region AI control (server-side, called by NPCRaceManager)


## Set the navigation destination. Cheap to call every tick — only triggers a
## path recalculation when the target actually moved.
func set_nav_target(pos: Vector3) -> void:
	_has_target = true
	if pos.distance_squared_to(_last_target_pos) < RETARGET_DISTANCE_SQ:
		return
	_last_target_pos = pos
	nav_agent.set_target_position(pos)


func clear_nav_target() -> void:
	_has_target = false


## Cosmetic only — the bot stops and the rig reads as wiped out (no ragdoll v1).
## NPCRaceManager owns the recovery timer + teleport back to the respawn point.
func crash() -> void:
	npc_state = NPCState.CRASHED
	velocity = Vector3.ZERO


## Cosmetic stub — v1 has no trick variety; kept as the hook for it.
func wheelie() -> void:
	npc_state = NPCState.WHEELIE


func stop_wheelie() -> void:
	npc_state = NPCState.RIDING


func finish() -> void:
	npc_state = NPCState.FINISHED
	clear_nav_target()


## Teleport (crash recovery / grid placement). Resets driving state.
func teleport_to(pos: Vector3, basis: Basis) -> void:
	global_transform = Transform3D(basis, pos)
	velocity = Vector3.ZERO
	npc_state = NPCState.RIDING
	# Force a fresh path from the new position on the next set_nav_target.
	_last_target_pos = Vector3.INF


#endregion


func _face_velocity(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length_squared() < 0.25:
		return
	# +Z faces the travel direction (bike front is +Z, see class docstring).
	var target_yaw := atan2(horizontal.x, horizontal.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	velocity.x = safe_velocity.x
	velocity.z = safe_velocity.z
	move_and_slide()


func _get_configuration_warnings() -> PackedStringArray:
	var issues := PackedStringArray()
	if bike_definition == null:
		issues.append("bike_definition must not be empty")
	if character_definition == null:
		issues.append("character_definition must not be empty")
	if animation_controller == null:
		issues.append("animation_controller must not be empty")
	return issues
