@tool
class_name SpawnManager extends BaseManager

signal player_spawned(player: PlayerEntity)

@export var lobby_manager: LobbyManager
@export var level_manager: LevelManager
@export var audio_manager: AudioManager
@export var hud_manager: HUDManager
@export var settings_manager: SettingsManager
@export var gamemode_manager: GamemodeManager

## In-place respawn is only safe on ground the bike can stand on. Steeper than this at the
## respawn site → fall back to the last flat breadcrumb.
const RESPAWN_STEEP_SLOPE_DEG: float = 35.0
## A breadcrumb is only recorded on ground at least this gentle.
const RESPAWN_FLAT_MAX_SLOPE_DEG: float = 25.0
const BREADCRUMB_INTERVAL_SECS: float = 1.0

## Server-only: last known flat-ground transform per peer. In-place respawns fall back here
## when the site is a ramp/loop/steep grade (or has no ground at all — e.g. fell out of the
## map), which otherwise loops the steep-slope stall crash.
var _flat_breadcrumbs: Dictionary[int, Transform3D] = {}
var _breadcrumb_accum: float = 0.0


func _ready():
	if Engine.is_editor_hint():
		return
	lobby_manager.lobby_players_updated.connect(_on_lobby_players_updated)


## Server-only: periodically remember each spawned player's last flat-ground transform, so an
## in-place respawn on a steep site (ramp, wall, off-map) can fall back somewhere safe.
func _physics_process(delta: float):
	if Engine.is_editor_hint() or multiplayer.multiplayer_peer == null or !multiplayer.is_server():
		return
	_breadcrumb_accum -= delta
	if _breadcrumb_accum > 0.0:
		return
	_breadcrumb_accum = BREADCRUMB_INTERVAL_SECS
	for peer_id in lobby_manager.lobby_players:
		# Player may not be spawned yet (late-join) — skip is intentional.
		var player := _get_player_by_peer_id(peer_id)
		if player == null or player.is_crashed:
			continue
		var normal := _ground_normal_at(player)
		if (
			normal != Vector3.ZERO
			and normal.angle_to(Vector3.UP) <= deg_to_rad(RESPAWN_FLAT_MAX_SLOPE_DEG)
		):
			_flat_breadcrumbs[peer_id] = Transform3D(
				Basis(Vector3.UP, player.global_rotation.y), player.global_position
			)


## Spawn all players from lobby_players dict (server only)
func spawn_all_players():
	if !multiplayer.is_server():
		return

	for peer_id in lobby_manager.lobby_players:
		var player_def: PlayerDefinition = lobby_manager.lobby_players[peer_id]
		rpc_spawn_player.rpc(peer_id, player_def.to_dict())


## Server broadcasts to all peers to spawn a player
@rpc("call_local", "reliable")
func rpc_spawn_player(peer_id: int, player_def_dict: Dictionary):
	add_player_locally(peer_id, player_def_dict)


## Server broadcasts to all peers to despawn a player
@rpc("call_local", "reliable")
func rpc_despawn_player(peer_id: int):
	remove_player_locally(peer_id)


## Update all spawned players' skins from lobby data.
func _on_lobby_players_updated(players: Dictionary):
	if level_manager.current_level.no_player_spawn_needed:
		return

	for peer_id in players:
		# Player may not be spawned yet during late-join sync — skip is intentional
		var player := _get_player_by_peer_id(peer_id)
		if player == null:
			continue
		player.update_skins(players[peer_id].bike_skin, players[peer_id].character_skin)


## True when the executing RPC came from the server or a local call — sender id is
## the local peer's own id for call_local execution (1 on the host) and 1 for
## server-sent RPCs. The broadcast RPCs below stay any_peer only because the server
## must call_local them; this closes them to clients.
func _sender_is_server() -> bool:
	return multiplayer.get_remote_sender_id() <= 1


## Client-callable: ask the server to respawn YOU (pause-menu button). The server
## derives the target from the sender — a client can never respawn someone else.
@rpc("any_peer", "call_local", "reliable")
func request_respawn():
	if !multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	# sender == 1 covers both the host's local call and (impossibly) server-sent.
	respawn_player.rpc(sender if sender > 1 else 1)


## Client-callable: quick-respawn YOU in place (R tap). The server derives the target from the
## sender and resolves the transform, so a client can never respawn someone else.
@rpc("any_peer", "call_local", "reliable")
func request_respawn_in_place():
	if !multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	respawn_in_place(sender if sender > 1 else 1)


## Server-only: resolve where a player should respawn in place — current spot upright, or the
## last flat breadcrumb if the site is too steep — and broadcast it. Shared by the R tap
## (request_respawn_in_place) and free-roam crash recovery so both behave identically.
func respawn_in_place(player_peer_id: int):
	var player := _get_player_by_peer_id(player_peer_id)
	var normal := _ground_normal_at(player)
	var too_steep := (
		normal == Vector3.ZERO or normal.angle_to(Vector3.UP) > deg_to_rad(RESPAWN_STEEP_SLOPE_DEG)
	)
	if too_steep and _flat_breadcrumbs.has(player_peer_id):
		var crumb := _flat_breadcrumbs[player_peer_id]
		respawn_player_in_place.rpc(player_peer_id, crumb.origin, crumb.basis)
		return
	var upright := Basis(Vector3.UP, player.global_rotation.y)
	respawn_player_in_place.rpc(player_peer_id, player.global_position, upright)


## Ground normal just under the player, Vector3.ZERO when there is no ground within 3m.
func _ground_normal_at(player: PlayerEntity) -> Vector3:
	var pos := player.global_position
	var space_state := get_viewport().get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP, pos + Vector3.DOWN * 3.0)
	# World geometry only: exclude the bike's own capsule (the ray starts just above its top, so
	# it self-hits and reports the bike's up-vector as "ground"), and mask to layer 1 so
	# crash-site ragdoll bones (layer 3) and other racers' layer-2 bits can't answer for the
	# ground either. A miss errs toward the breadcrumb fallback — the safe direction.
	query.exclude = [player.get_rid()]
	query.collision_mask = 1
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.ZERO
	return hit["normal"]


## Set player's rb_do_respawn to true on every peer so each runs do_respawn() locally.
## Required so client-only state (ragdoll bones, controller-local vars) gets reset alongside
## the server-synced global_transform / is_crashed.
@rpc("any_peer", "call_local", "reliable")
func respawn_player(player_peer_id: int):
	if !_sender_is_server():
		return
	_get_player_by_peer_id(player_peer_id).rb_do_respawn = true


## Set player's rb_do_crash on every peer so each runs the crash locally (ragdoll,
## camera and audio are client-side). Sent by whoever rammed them — a rider can't
## detect being hit, only what it moved into. Server only; see CrashController and
## NPCTrafficState for the detection side.
@rpc("any_peer", "call_local", "reliable")
func crash_player(player_peer_id: int):
	if !_sender_is_server():
		return
	_get_player_by_peer_id(player_peer_id).rb_do_crash = true


## Set player's rb_do_wobble on every peer so each injects the wobble in its rollback tick
## (wobble_vel is synced state). Server only — the callable the bat and any wobble source uses.
@rpc("any_peer", "call_local", "reliable")
func wobble_player(player_peer_id: int, strength: float):
	if !_sender_is_server():
		return
	var player := _get_player_by_peer_id(player_peer_id)
	player.rb_wobble_strength = strength
	player.rb_do_wobble = true


## Set player's rb_add_boost on every peer so each adds one boost segment in its rollback tick
## (boost_amount is synced state). Server only — sent when a rider collects a Gas Can pickup.
@rpc("any_peer", "call_local", "reliable")
func grant_boost(player_peer_id: int):
	if !_sender_is_server():
		return
	_get_player_by_peer_id(player_peer_id).rb_add_boost = true


## Play the pickup "pop" (Ding) on the collecting rider's own client. Server → that peer via rpc_id.
@rpc("call_local", "reliable")
func play_pickup_sfx():
	audio_manager.play_ding()


## Debug: fill the player's boost meter. Server only; broadcast so each peer sets the setter and
## fills boost_amount in its own rollback tick (boost_amount is synced state).
@rpc("any_peer", "call_local", "reliable")
func max_boost_player(player_peer_id: int):
	if !_sender_is_server():
		return
	_get_player_by_peer_id(player_peer_id).rb_do_max_boost = true


## Respawn player at a specific transform AND store it as the persistent respawn point
## (used by subsequent crash respawns until reset). Runs on every peer.
@rpc("any_peer", "call_local", "reliable")
func respawn_player_at(player_peer_id: int, pos: Vector3, basis: Basis):
	if !_sender_is_server():
		return
	var player_node := _get_player_by_peer_id(player_peer_id)
	player_node.rb_respawn_transform = Transform3D(basis, pos)
	player_node.rb_do_respawn = true


## Respawn a player at a one-shot transform WITHOUT changing the persistent respawn point.
## Free roam crash respawns use this so you respawn where you crashed, while the pause-menu
## respawn button still returns to the original spawn (rb_respawn_transform). Runs on every peer.
@rpc("any_peer", "call_local", "reliable")
func respawn_player_in_place(player_peer_id: int, pos: Vector3, basis: Basis):
	if !_sender_is_server():
		return
	var player_node := _get_player_by_peer_id(player_peer_id)
	player_node.rb_respawn_transform_oneshot = Transform3D(basis, pos)
	player_node.rb_do_respawn = true


## Update the persistent respawn point without teleporting. Used when a player
## passes a race checkpoint — their next crash returns them here.
@rpc("any_peer", "call_local", "reliable")
func set_respawn_point(player_peer_id: int, pos: Vector3, basis: Basis):
	if !_sender_is_server():
		return
	_get_player_by_peer_id(player_peer_id).rb_respawn_transform = Transform3D(basis, pos)


## Clear the persistent respawn point so the next respawn falls back to player_spawn_pos.
## Used when entering free roam from another gamemode.
@rpc("any_peer", "call_local", "reliable")
func reset_respawn_point(player_peer_id: int):
	if !_sender_is_server():
		return
	_get_player_by_peer_id(player_peer_id).rb_respawn_transform = Transform3D()


## Instantiate and add player node locally (no authority check)
func add_player_locally(peer_id: int, player_def_dict: Dictionary):
	var player_def = PlayerDefinition.new()
	player_def.from_dict(player_def_dict)

	DebugUtils.DebugMsg("Adding player locally: %s - %s" % [peer_id, player_def.username])

	var player_to_add = (
		level_manager.current_level.player_entity_scene.instantiate() as PlayerEntity
	)
	player_to_add.name = str(peer_id)
	player_to_add.audio_manager = audio_manager # HACK
	player_to_add.settings_manager = settings_manager # HACK
	player_to_add.gamemode_manager = gamemode_manager # HACK
	player_to_add.hud_manager = hud_manager # HACK
	player_to_add.bike_definition = player_def.bike_skin
	player_to_add.character_definition = player_def.character_skin

	level_manager.current_level.player_spawn_pos.add_child(player_to_add, true)
	player_to_add.username = player_def.username
	player_spawned.emit(player_to_add)


## Remove player node locally (no authority check)
func remove_player_locally(peer_id: int):
	_flat_breadcrumbs.erase(peer_id)  # server-only dict; harmless no-op on clients
	if !level_manager.current_level.player_spawn_pos.has_node(str(peer_id)):
		return

	level_manager.current_level.player_spawn_pos.get_node(str(peer_id)).queue_free()


## Get player from multiplayer peer id found in level_manager.current_level
func _get_player_by_peer_id(player_peer_id: int) -> PlayerEntity:
	var player_node: PlayerEntity
	for child in level_manager.current_level.player_spawn_pos.get_children():
		if child is PlayerEntity:
			if child.name == str(player_peer_id):
				player_node = child
				break
	return player_node


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if audio_manager == null:
		issues.append("audio_manager must not be empty")
	if lobby_manager == null:
		issues.append("lobby_manager must not be empty")
	if level_manager == null:
		issues.append("level_manager must not be empty")
	if settings_manager == null:
		issues.append("settings_manager must not be empty")
	if gamemode_manager == null:
		issues.append("gamemode_manager must not be empty")
	if hud_manager == null:
		issues.append("hud_manager must not be empty")

	return issues
