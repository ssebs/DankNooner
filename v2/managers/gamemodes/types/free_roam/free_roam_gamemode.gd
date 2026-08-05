@tool
class_name FreeRoamGameMode extends GameModeType

@export var game_mode_event_confirm_hud: GameModeEventConfirmHUD
@export var level_manager: LevelManager
@export var npc_traffic_manager: NPCTrafficManager
@export var animal_spawn_manager: AnimalSpawnManager

## Crash-site respawn is only safe on ground the bike can actually stand on.
## Steeper than this at the crash site → fall back to the last flat breadcrumb.
const RESPAWN_STEEP_SLOPE_DEG: float = 35.0
## A breadcrumb is only recorded on ground at least this gentle.
const RESPAWN_FLAT_MAX_SLOPE_DEG: float = 25.0
const BREADCRUMB_INTERVAL_SECS: float = 1.0

var _respawn_delay: float = 3.0

var _ctx: GamemodeStateContext

## Server-only: last known flat-ground transform per peer. Crash respawns fall back
## here when the crash site is a ramp/loop/steep grade (or has no ground at all —
## e.g. fell out of the map), which otherwise loops the steep-slope stall crash.
var _flat_breadcrumbs: Dictionary[int, Transform3D] = {}
var _breadcrumb_accum: float = 0.0


#override
func is_late_joinable() -> bool:
	return true


func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	_breadcrumb_accum = 0.0
	if state_context is GamemodeStateContext:
		_ctx = state_context
	else:
		_ctx = GamemodeStateContext.new()
		_ctx.peer_id = multiplayer.get_unique_id()
	gamemode_manager.current_game_mode = GameModeType.Kind.FREE_ROAM
	DebugUtils.DebugMsg("FreeRoam Mode")

	gamemode_manager.player_crashed.connect(_on_player_crashed)
	gamemode_manager.player_disconnected.connect(_on_player_disconnected)
	gamemode_manager.player_latejoined.connect(_on_player_latejoined)

	_signals_event_circles(true)

	# Hide + disable every event's objects (checkpoints, etc.) â€” they only show
	# while their own gamemode is running. Initial-load default and return path.
	for event_start_circle in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["EventCircles"]):
		(event_start_circle as EventStartCircle).disable_game_objects()

	# Only spawn if players aren't already in the level (e.g. coming from another gamemode)
	if spawn_manager._get_player_by_peer_id(multiplayer.get_unique_id()) == null:
		spawn_manager.spawn_all_players()

	if multiplayer.is_server():
		# Distribute every peer to a unique spot. With grid_markers, each peer gets
		# its own grid slot (and persistent respawn point). Without, fall back to
		# the legacy single-spawn behavior.
		# Must hit every peer, not just _ctx.peer_id â€” that's only the player who
		# triggered the transition (the server, for race end), leaving clients riding.
		var grid_markers: Array[Marker3D] = level_manager.current_level.grid_markers
		var slot: int = 0
		for peer_id in gamemode_manager.lobby_manager.lobby_players:
			if grid_markers.is_empty():
				spawn_manager.reset_respawn_point.rpc(peer_id)
				spawn_manager.respawn_player.rpc(peer_id)
			else:
				var idx: int = min(slot, grid_markers.size() - 1)
				var marker := grid_markers[idx]
				spawn_manager.respawn_player_at.rpc(
					peer_id, marker.global_position, marker.global_basis
				)
				slot += 1

		npc_traffic_manager.start_traffic()
		animal_spawn_manager.start_animals()
	else:
		# Our level just finished loading — pull any traffic spawned before we could
		# accept it (fresh-start broadcasts race our spawn_level; late join misses
		# them entirely).
		npc_traffic_manager.request_traffic_sync()
		animal_spawn_manager.request_animal_sync()


func Physics_Update(delta: float):
	if Engine.is_editor_hint() or !multiplayer.is_server():
		return
	_breadcrumb_accum -= delta
	if _breadcrumb_accum > 0.0:
		return
	_breadcrumb_accum = BREADCRUMB_INTERVAL_SECS
	for peer_id in gamemode_manager.lobby_manager.lobby_players:
		# Player may not be spawned yet (late-join) — skip is intentional.
		var player := spawn_manager._get_player_by_peer_id(peer_id)
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


## Ground normal just under the player, Vector3.ZERO when there is no ground within 3m.
func _ground_normal_at(player: PlayerEntity) -> Vector3:
	var pos := player.global_position
	var space_state := get_viewport().get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP, pos + Vector3.DOWN * 3.0)
	# World geometry only: exclude the bike's own capsule (the ray starts just above
	# its top, so it self-hits and reports the bike's up-vector as "ground"), and
	# mask to layer 1 so crash-site ragdoll bones (layer 3) and other racers'
	# layer-2 bits can't answer for the ground either. A miss errs toward the
	# breadcrumb fallback — the safe direction.
	query.exclude = [player.get_rid()]
	query.collision_mask = 1
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.ZERO
	return hit["normal"]


## param is whether to connect() or disconnect()
func _signals_event_circles(should_connect: bool):
	for event_start_circle in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["EventCircles"]):
		event_start_circle = event_start_circle as EventStartCircle
		if should_connect:
			event_start_circle.entered_event_circle.connect(_on_event_circle_entered)
			event_start_circle.exited_event_circle.connect(_on_event_circle_exited)
		else:
			event_start_circle.entered_event_circle.disconnect(_on_event_circle_entered)
			event_start_circle.exited_event_circle.disconnect(_on_event_circle_exited)


func _on_event_circle_entered(peer_id: int, source_circle: EventStartCircle):
	var ev := source_circle.gamemode_event
	DebugUtils.DebugMsg("%d entered eventcircle: %s" % [peer_id, ev.name])

	_ctx.gamemode_event = ev
	_ctx.event_start_circle = source_circle

	game_mode_event_confirm_hud.on_player_entered_circle.rpc_id(1, peer_id, ev.name, ev.description)

	# connect hud signals
	if not game_mode_event_confirm_hud.hud_submitted.is_connected(
		_on_game_mode_event_confirm_hud_submitted
	):
		game_mode_event_confirm_hud.hud_submitted.connect(_on_game_mode_event_confirm_hud_submitted)

	# TODO - set player velocity to 0


func _on_event_circle_exited(peer_id: int, source_circle: EventStartCircle):
	DebugUtils.DebugMsg("%d exited eventcircle: %s" % [peer_id, source_circle.gamemode_event.name])

	if game_mode_event_confirm_hud.hud_submitted.is_connected(
		_on_game_mode_event_confirm_hud_submitted
	):
		game_mode_event_confirm_hud.hud_submitted.disconnect(
			_on_game_mode_event_confirm_hud_submitted
		)

	game_mode_event_confirm_hud.on_player_close_pressed.rpc_id(1, peer_id)


func _on_game_mode_event_confirm_hud_submitted(peer_id: int):
	DebugUtils.DebugMsg("Starting Event... %d" % peer_id)
	game_mode_event_confirm_hud.on_player_close_pressed.rpc_id(1, peer_id)
	gamemode_manager.change_gamemode.rpc_id(
		1, _ctx.gamemode_event.target_gamemode, peer_id, _ctx.event_start_circle.get_path()
	)


func Exit(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.player_crashed.disconnect(_on_player_crashed)
	gamemode_manager.player_disconnected.disconnect(_on_player_disconnected)
	gamemode_manager.player_latejoined.disconnect(_on_player_latejoined)

	_signals_event_circles(false)

	if multiplayer.is_server():
		npc_traffic_manager.stop_traffic()
		animal_spawn_manager.stop_animals()
	else:
		npc_traffic_manager.reset_local_traffic()
		animal_spawn_manager.reset_local_animals()

	_flat_breadcrumbs.clear()


func _on_player_crashed(peer_id: int):
	if !multiplayer.is_server():
		return

	get_tree().create_timer(_respawn_delay).timeout.connect(
		func(): _respawn_at_crash_site(peer_id), CONNECT_ONE_SHOT
	)


## Free roam respawns you where you crashed (upright, same heading) rather than back at
## spawn. Doesn't touch the persistent respawn point, so the pause-menu respawn button
## still returns to the original spawn.
func _respawn_at_crash_site(peer_id: int):
	var player := spawn_manager._get_player_by_peer_id(peer_id)
	# Already recovered (e.g. pause-menu respawn button) before the timer fired â€” skip
	# so we don't respawn a second time.
	if not player.is_crashed:
		return
	var normal := _ground_normal_at(player)
	var too_steep := (
		normal == Vector3.ZERO or normal.angle_to(Vector3.UP) > deg_to_rad(RESPAWN_STEEP_SLOPE_DEG)
	)
	if too_steep and _flat_breadcrumbs.has(peer_id):
		var crumb := _flat_breadcrumbs[peer_id]
		spawn_manager.respawn_player_in_place.rpc(peer_id, crumb.origin, crumb.basis)
		return
	var upright := Basis(Vector3.UP, player.global_rotation.y)
	spawn_manager.respawn_player_in_place.rpc(peer_id, player.global_position, upright)


func _on_player_latejoined(peer_id: int):
	gamemode_manager.latespawn_player(peer_id)


func _on_player_disconnected(peer_id: int):
	_flat_breadcrumbs.erase(peer_id)
	if gamemode_manager.match_state == GamemodeManager.MatchState.IN_GAME:
		spawn_manager.rpc_despawn_player.rpc(peer_id)


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if game_mode_event_confirm_hud == null:
		issues.append("game_mode_event_confirm_hud must not be empty")
	if level_manager == null:
		issues.append("level_manager must not be empty")
	if npc_traffic_manager == null:
		issues.append("npc_traffic_manager must not be empty")
	if animal_spawn_manager == null:
		issues.append("animal_spawn_manager must not be empty")

	return issues
