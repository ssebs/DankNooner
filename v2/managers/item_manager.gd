@tool
## Server authority for pickup items. Instant items (Gas Can) apply on collect; the rest fill the
## rider's single held slot and are spent by double-tapping the trick button or the use_item action
## (InputStateManager → request_use_item). Deployables (oil slick, ramp) are level children spawned
## on every peer by RPC-by-path, the same model as PickupSpawner.
class_name ItemManager extends BaseManager

@export var level_manager: LevelManager
@export var spawn_manager: SpawnManager
@export var gamemode_manager: GamemodeManager
@export var riding_hud_state: RidingHUDState
@export var audio_manager: AudioManager

@export_group("Oil Slick")
@export var oil_slick_drop_distance: float = 3.0
@export var oil_slick_lifetime: float = 30.0
## The dropper rides through their own slick for this long, then it can catch them too.
@export var oil_slick_owner_grace: float = 2.0

@export_group("Ramp")
## Spawned this many seconds of travel ahead, but never closer than ramp_min_distance.
@export var ramp_lead_time: float = 0.6
@export var ramp_min_distance: float = 8.0
@export var ramp_lifetime: float = 8.0

@export_group("Rally Up")
## Seconds everyone rides the mini bike as the astronaut before their own skins come back.
@export var rally_up_duration: float = 10.0

const OIL_SLICK_SCENE := preload("res://levels/components/pickups/oil_slick.tscn")
const RAMP_SCENE := preload("res://levels/components/pickups/deployable_ramp.tscn")
const RALLY_UP_BIKE := preload("res://resources/bikes/skins/mini_default_skin_definition.tres")
const RALLY_UP_CHARACTER := preload(
	"res://resources/player/skins/astronaut_default_skin_definition.tres"
)

## Server-only: peer_id -> the item they're holding. No entry = empty slot.
var _held: Dictionary[int, PickupItemDefinition] = {}
## Server-only: suffix for deployable node names, so despawns can find them by path.
var _next_deployable_id: int = 0
## Server-only: bumped per Rally Up so an earlier use's timer can't end a later one early.
var _rally_up_id: int = 0


func _ready():
	if Engine.is_editor_hint():
		return
	gamemode_manager.player_disconnected.connect(_on_player_disconnected)


## Server-only. Returns false (pickup stays put) when a held item would overflow the slot.
func collect(peer_id: int, definition: PickupItemDefinition) -> bool:
	var item_type := definition.item_type
	if item_type == PickupItemDefinition.PickupItemType.GAS_CAN:
		spawn_manager.grant_boost.rpc(peer_id)
	elif _held.has(peer_id):
		return false
	else:
		_held[peer_id] = definition
		riding_hud_state.push_held_item(peer_id, definition)
		if item_type == PickupItemDefinition.PickupItemType.SHOTGUN:
			_rpc_set_shotgun_held.rpc(peer_id, true)
	spawn_manager.play_pickup_sfx.rpc_id(peer_id)
	return true


## Server-only. Empties every slot — a new pickup session (race start, free roam) starts clean.
func clear_items() -> void:
	for peer_id in _held:
		riding_hud_state.push_held_item(peer_id, null)
		if _held[peer_id].item_type == PickupItemDefinition.PickupItemType.SHOTGUN:
			_rpc_set_shotgun_held.rpc(peer_id, false)
	_held.clear()


## Client-callable: use YOUR held item. The server derives the rider from the sender.
@rpc("any_peer", "call_local", "reliable")
func request_use_item():
	if !multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender > 1 else 1
	var player := spawn_manager.get_player_by_peer_id(peer_id)
	# Empty-handed double taps are normal trick-button use, and a crashed rider can't use items.
	if !_held.has(peer_id) or player.is_crashed:
		return
	var definition := _held[peer_id]
	_held.erase(peer_id)
	riding_hud_state.push_held_item(peer_id, null)
	_rpc_play_use_sfx.rpc_id(peer_id, definition.use_sfx)
	match definition.item_type:
		PickupItemDefinition.PickupItemType.BAT:
			spawn_manager.swing_bat.rpc(peer_id)
		PickupItemDefinition.PickupItemType.OIL_SLICK:
			_drop_oil_slick(peer_id, player)
		PickupItemDefinition.PickupItemType.RAMP:
			_place_ramp(player)
		PickupItemDefinition.PickupItemType.SHOTGUN:
			_fire_shotgun(peer_id, player)
		PickupItemDefinition.PickupItemType.RALLY_UP:
			_rally_up()


## The user's own client — SoundEvents aren't positional, so everyone else hearing it would be noise.
@rpc("call_local", "reliable")
func _rpc_play_use_sfx(sfx: AudioManager.Sfx):
	audio_manager.play_sfx(sfx)


func _on_player_disconnected(peer_id: int) -> void:
	_held.erase(peer_id)


#region Oil slick / ramp (server places, every peer spawns)


func _drop_oil_slick(peer_id: int, player: PlayerEntity) -> void:
	var xform := _ground_transform(player, -oil_slick_drop_distance)
	var slick_name := _next_deployable_name()
	_rpc_spawn_oil_slick.rpc(slick_name, xform, peer_id, Time.get_ticks_msec())
	_despawn_after(slick_name, oil_slick_lifetime)


func _place_ramp(player: PlayerEntity) -> void:
	var distance := maxf(player.velocity.length() * ramp_lead_time, ramp_min_distance)
	var ramp_name := _next_deployable_name()
	_rpc_spawn_ramp.rpc(ramp_name, _ground_transform(player, distance))
	_despawn_after(ramp_name, ramp_lifetime)


## Transform `distance` along the rider's heading (negative = behind), snapped to the ground there.
func _ground_transform(player: PlayerEntity, distance: float) -> Transform3D:
	var basis := Basis(Vector3.UP, player.global_rotation.y)
	var pos := player.global_position - basis.z * distance
	# Slopes can put the ground up to ~|distance| above or below the rider at that spot
	var reach := Vector3.UP * absf(distance)
	var query := PhysicsRayQueryParameters3D.create(pos + reach, pos - reach)
	query.exclude = [player.get_rid()]
	query.collision_mask = 1
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(query)
	# No ground in reach (e.g. deployed off a jump) — leave it level at rider height, intentional
	if hit.is_empty():
		return Transform3D(basis, pos)
	var up: Vector3 = hit["normal"]
	var back := basis.z.slide(up).normalized()
	return Transform3D(Basis(up.cross(back), up, back), hit["position"])


func _next_deployable_name() -> String:
	_next_deployable_id += 1
	return "Deployable%d" % _next_deployable_id


func _despawn_after(node_name: String, secs: float) -> void:
	get_tree().create_timer(secs).timeout.connect(
		func(): _rpc_despawn_deployable.rpc(node_name), CONNECT_ONE_SHOT
	)


@rpc("call_local", "reliable")
func _rpc_spawn_oil_slick(
	slick_name: String, xform: Transform3D, owner_peer_id: int, dropped_msec: int
):
	var slick: Area3D = OIL_SLICK_SCENE.instantiate()
	slick.name = slick_name
	level_manager.current_level.add_child(slick)
	slick.global_transform = xform
	# Only the server decides a hit — clients just show the slick.
	if multiplayer.is_server():
		slick.body_entered.connect(
			_on_oil_slick_body_entered.bind(slick_name, owner_peer_id, dropped_msec)
		)


@rpc("call_local", "reliable")
func _rpc_spawn_ramp(ramp_name: String, xform: Transform3D):
	var ramp: Node3D = RAMP_SCENE.instantiate()
	ramp.name = ramp_name
	level_manager.current_level.add_child(ramp)
	ramp.global_transform = xform


@rpc("call_local", "reliable")
func _rpc_despawn_deployable(node_name: String):
	# Already consumed, or the level changed and took it with it — skip is intentional.
	var node := level_manager.current_level.get_node_or_null(node_name)
	if node != null:
		node.queue_free()


## Server-only. NPC racers ride through, and a rider already down doesn't use it up.
func _on_oil_slick_body_entered(
	body: Node3D, slick_name: String, owner_peer_id: int, dropped_msec: int
) -> void:
	if not body is PlayerEntity or body.is_crashed:
		return
	var victim_id := int(body.name)
	var in_grace := Time.get_ticks_msec() - dropped_msec < oil_slick_owner_grace * 1000.0
	if victim_id == owner_peer_id and in_grace:
		return
	spawn_manager.knock_out(victim_id, owner_peer_id)
	_rpc_despawn_deployable.rpc(slick_name)


#endregion

#region Rally Up


## Server-only. Everyone (user included) swaps to the mini bike + astronaut until the timer ends.
func _rally_up() -> void:
	_rally_up_id += 1
	_rpc_set_rally_up.rpc(true)
	get_tree().create_timer(rally_up_duration).timeout.connect(
		_end_rally_up.bind(_rally_up_id), CONNECT_ONE_SHOT
	)


func _end_rally_up(id: int) -> void:
	if id == _rally_up_id:
		_rpc_set_rally_up.rpc(false)


## Every peer. Ending restores each rider's lobby skins, or the event's forced bike if it has one.
@rpc("call_local", "reliable")
func _rpc_set_rally_up(active: bool):
	var forced: BikeSkinDefinition = null
	if gamemode_manager.current_event != null:
		forced = gamemode_manager.current_event.definition.forced_base_bike
	var lobby_players := gamemode_manager.lobby_manager.lobby_players
	for peer_id in lobby_players:
		# Not spawned (late join), or the level changed before the timer ended — skip is intentional
		var player := spawn_manager.get_player_by_peer_id(peer_id)
		if player == null:
			continue
		if active:
			player.update_skins(RALLY_UP_BIKE, RALLY_UP_CHARACTER)
		else:
			var lobby_def := lobby_players[peer_id]
			player.update_skins(forced if forced else lobby_def.bike_skin, lobby_def.character_skin)


#endregion

#region Shotgun


## Server-only. Knocks out the nearest other rider inside the shooter's %GunCollisionArea.
## Toggle Debug > Visible Collision Shapes to see the hitbox.
func _fire_shotgun(peer_id: int, shooter: PlayerEntity) -> void:
	_rpc_fire_shotgun.rpc(peer_id)
	var in_hitbox: Array[Node3D] = shooter.get_node("%GunCollisionArea").get_overlapping_bodies()
	var target: PlayerEntity = null
	var nearest := INF
	for body in in_hitbox:
		if not body is PlayerEntity or body == shooter or body.is_crashed:
			continue
		var dist := shooter.global_position.distance_to(body.global_position)
		if dist < nearest:
			target = body
			nearest = dist
	DebugUtils.DebugMsg(
		"shotgun: %d bodies in hitbox, hit %s" % [in_hitbox.size(), target.name if target else "none"]
	)
	# Nobody in the hitbox is a plain miss.
	if target != null:
		spawn_manager.knock_out(int(target.name), peer_id)


## Every peer: the holder's equip pose follows the held shotgun.
@rpc("call_local", "reliable")
func _rpc_set_shotgun_held(peer_id: int, held: bool):
	spawn_manager.get_player_by_peer_id(peer_id).animation_controller.shotgun_held = held


## Every peer: fire, then unequip (AnimationController clears shotgun_held after the shot).
@rpc("call_local", "reliable")
func _rpc_fire_shotgun(peer_id: int):
	spawn_manager.get_player_by_peer_id(peer_id).animation_controller.play_shotgun_fire()


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	if level_manager == null:
		issues.append("level_manager must not be empty")
	if spawn_manager == null:
		issues.append("spawn_manager must not be empty")
	if gamemode_manager == null:
		issues.append("gamemode_manager must not be empty")
	if riding_hud_state == null:
		issues.append("riding_hud_state must not be empty")
	if audio_manager == null:
		issues.append("audio_manager must not be empty")
	return issues
