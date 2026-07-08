## Kinematic AI race rider — it just moves and collides. No netfox rollback,
## no input simulation, no bike physics. The server simulates (NPCRaceManager
## sets nav targets and owns crash/respawn timers); clients are passive and
## receive `transform` + `npc_state` via the child MultiplayerSynchronizer.
##
## VisualRoot is yawed 180° (matching the player scene), so the bike front is
## entity -Z; steering yaws the body to face velocity with -Z.
class_name NPCRiderEntity extends CharacterBody3D

enum NPCState { RIDING, WHEELIE, CRASHED, FINISHED }

@export var bike_definition: BikeSkinDefinition
@export var character_definition: CharacterSkinDefinition
@export var animation_controller: NPCAnimationController
@export var move_speed: float = 35.0
## Speed ramp rates (units/s^2) — accel when speeding up, braking when slowing.
@export var acceleration: float = 64.0
@export var braking: float = 40.0
## Speed floor through the sharpest turns. The bot eases down toward this as the
## road bends ahead, then accelerates back to move_speed as it straightens.
@export var min_turn_speed: float = 8.0
## Exponent on the road's bend — higher brakes harder for the same corner
## (1 = linear, so even gentle turns shed speed as this climbs).
@export var turn_sharpness: float = 4.0
## How far ahead along the nav path (metres) to read the road's bend when
## picking corner speed — larger = brakes earlier for upcoming turns.
@export var turn_lookahead: float = 12.0
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
## Current horizontal speed magnitude, ramped toward the turn-scaled target.
var _speed: float = 0.0


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

	# Don't gate on is_navigation_finished(): a checkpoint is a gate to drive
	# THROUGH, not a point to stop at. target_desired_distance (3m) is larger
	# than the checkpoint trigger is deep (1m), so stopping on "arrival" parks
	# the bot short of the trigger and its lap never advances. Keep driving at
	# the target — the crossing retargets it to the next checkpoint.
	var driving := _has_target and npc_state != NPCState.CRASHED and npc_state != NPCState.FINISHED
	if driving:
		var next_pos := nav_agent.get_next_path_position()
		var dir := next_pos - global_position
		dir.y = 0.0
		dir = dir.normalized()

		# Corner speed reads the road's bend over the next `turn_lookahead` metres,
		# sampled along the nav path by arc length (so it doesn't care how the
		# navmesh spaces its corners). Compare the road's heading over the near
		# half of the window vs the far half: straight -> move_speed, a bend eases
		# toward min_turn_speed. Because we look ahead, the bot brakes BEFORE the
		# apex and accelerates back out as the road straightens.
		var mid := _path_point_ahead(turn_lookahead)
		var far := _path_point_ahead(turn_lookahead * 2.0)
		var lead := mid - global_position
		var trail := far - mid
		lead.y = 0.0
		trail.y = 0.0
		var alignment := 1.0
		if lead.length_squared() > 0.01 and trail.length_squared() > 0.01:
			alignment = clampf(lead.normalized().dot(trail.normalized()), 0.0, 1.0)
		var turn_factor := pow(alignment, turn_sharpness)
		var target_speed := lerpf(min_turn_speed, move_speed, turn_factor)
		var rate := acceleration if target_speed > _speed else braking
		_speed = move_toward(_speed, target_speed, rate * delta)

		velocity.x = dir.x * _speed
		velocity.z = dir.z * _speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, braking * delta)
		velocity.z = move_toward(velocity.z, 0.0, braking * delta)
		_speed = Vector2(velocity.x, velocity.z).length()

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
	DebugUtils.DebugMsg("NPC %s retarget -> %v" % [name, pos], OS.has_feature("debug"))


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
	_speed = 0.0
	npc_state = NPCState.RIDING
	# Force a fresh path from the new position on the next set_nav_target.
	_last_target_pos = Vector3.INF


#endregion


## Point on the current nav path `distance` metres ahead of us, measured by arc
## length along the path polyline. This makes the road's curvature read the same
## regardless of how sparsely/unevenly the navmesh spaces its corners.
func _path_point_ahead(distance: float) -> Vector3:
	var path := nav_agent.get_current_navigation_path()
	if path.size() < 2:
		return global_position
	var prev := global_position
	var remaining := distance
	for i in range(nav_agent.get_current_navigation_path_index(), path.size()):
		var seg := path[i] - prev
		var seg_len := seg.length()
		if seg_len >= remaining:
			return prev + seg.normalized() * remaining
		remaining -= seg_len
		prev = path[i]
	# Ran off the end of the path — clamp to the final point.
	return prev


func _face_velocity(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length_squared() < 0.25:
		return
	# -Z faces the travel direction (bike front is -Z, see class docstring).
	var target_yaw := atan2(-horizontal.x, -horizontal.z)
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
