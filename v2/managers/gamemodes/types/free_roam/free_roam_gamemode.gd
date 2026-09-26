@tool
class_name FreeRoamGameMode extends GameModeType

@export var game_mode_event_hud_state: GamemodeEventHUDState
@export var level_manager: LevelManager
## Optional — unlinked in main_game while traffic is disabled for perf; null skips traffic.
@export var npc_traffic_manager: NPCTrafficManager
@export var pickup_spawn_manager: PickupSpawnManager
@export var trick_manager: TrickManager
@export var riding_hud_state: RidingHUDState
@export var _respawn_delay: float = 2.5

## Trick round: banked combo points add up per human for ROUND_SECS, shown on the live
## leaderboard with the time left, then the winner is called out and it resets.
const ROUND_SECS: float = 60.0
const LEADERBOARD_REFRESH_SECS: float = 0.25

var _ctx: GamemodeStateContext
## peer_id -> points banked this round. Server only.
var _round_points: Dictionary[int, float] = {}
var _round_left: float = ROUND_SECS
var _leaderboard_refresh_accum: float = 0.0


#override
func is_late_joinable() -> bool:
	return true


func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return
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
	trick_manager.combo_banked.connect(_on_combo_banked)

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
		# Skipped when returning from a finished race — players stay where they finished.
		if !_ctx.skip_spawn_redistribute:
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

		if npc_traffic_manager != null:
			npc_traffic_manager.start_traffic()
		pickup_spawn_manager.activate_pickups()
		_round_points.clear()
		_round_left = ROUND_SECS
	else:
		# Our level just finished loading — pull any traffic spawned before we could
		# accept it (fresh-start broadcasts race our spawn_level; late join misses
		# them entirely).
		if npc_traffic_manager != null:
			npc_traffic_manager.request_traffic_sync()
		pickup_spawn_manager.request_pickup_sync()


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

	game_mode_event_hud_state.on_player_entered_circle.rpc_id(1, peer_id, ev.name, ev.description)

	# connect hud signals
	if not game_mode_event_hud_state.hud_submitted.is_connected(
		_on_game_mode_event_confirm_hud_submitted
	):
		game_mode_event_hud_state.hud_submitted.connect(_on_game_mode_event_confirm_hud_submitted)

	# TODO - set player velocity to 0


func _on_event_circle_exited(peer_id: int, source_circle: EventStartCircle):
	DebugUtils.DebugMsg("%d exited eventcircle: %s" % [peer_id, source_circle.gamemode_event.name])

	if game_mode_event_hud_state.hud_submitted.is_connected(
		_on_game_mode_event_confirm_hud_submitted
	):
		game_mode_event_hud_state.hud_submitted.disconnect(
			_on_game_mode_event_confirm_hud_submitted
		)

	game_mode_event_hud_state.on_player_close_pressed.rpc_id(1, peer_id)


func _on_game_mode_event_confirm_hud_submitted(peer_id: int):
	DebugUtils.DebugMsg("Starting Event... %d" % peer_id)
	game_mode_event_hud_state.on_player_close_pressed.rpc_id(1, peer_id)
	gamemode_manager.change_gamemode.rpc_id(
		1, _ctx.gamemode_event.target_gamemode, peer_id, _ctx.event_start_circle.get_path()
	)


func Exit(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.player_crashed.disconnect(_on_player_crashed)
	gamemode_manager.player_disconnected.disconnect(_on_player_disconnected)
	gamemode_manager.player_latejoined.disconnect(_on_player_latejoined)
	trick_manager.combo_banked.disconnect(_on_combo_banked)

	_signals_event_circles(false)

	if multiplayer.is_server():
		if npc_traffic_manager != null:
			npc_traffic_manager.stop_traffic()
		pickup_spawn_manager.deactivate_pickups()
		riding_hud_state.clear_leaderboard()
	elif npc_traffic_manager != null:
		npc_traffic_manager.reset_local_traffic()


func Update(delta: float):
	if Engine.is_editor_hint() or !multiplayer.is_server():
		return
	_round_left -= delta
	if _round_left <= 0.0:
		_end_round()
	_leaderboard_refresh_accum -= delta
	if _leaderboard_refresh_accum > 0.0:
		return
	_leaderboard_refresh_accum = LEADERBOARD_REFRESH_SECS
	var secs := ceili(_round_left)
	var headers := PackedStringArray(["⏱ %d:%02d" % [secs / 60, secs % 60], "💰"])
	riding_hud_state.push_leaderboard(headers, _leaderboard_rows(), PackedInt32Array())


#region Trick round (server only)


## Every spawned human, most points first.
func _leaderboard_rows() -> Array:
	var lobby_players := gamemode_manager.lobby_manager.lobby_players
	var peer_ids: Array[int] = []
	for peer_id in lobby_players:
		# Player may not be spawned yet (late-join) — skip is intentional.
		if spawn_manager._get_player_by_peer_id(peer_id) != null:
			peer_ids.append(peer_id)
	peer_ids.sort_custom(
		func(a, b): return _round_points.get(a, 0.0) > _round_points.get(b, 0.0)
	)
	var rows: Array = []
	for peer_id in peer_ids:
		var cells := PackedStringArray(
			[lobby_players[peer_id].username, "%d" % int(_round_points.get(peer_id, 0.0))]
		)
		rows.append({"peer_id": peer_id, "cells": cells})
	return rows


func _end_round():
	var lobby_players := gamemode_manager.lobby_manager.lobby_players
	var winner_id := -1
	var best := 0.0
	for peer_id in lobby_players:
		var points: float = _round_points.get(peer_id, 0.0)
		if points > best:
			best = points
			winner_id = peer_id
	# Nobody banked a combo this round — nothing to call out.
	if winner_id != -1:
		riding_hud_state.push_callout_all(
			tr("FREEROAM_ROUND_WINNER").format(
				{"name": lobby_players[winner_id].username, "points": int(best)}
			)
		)
	_round_points.clear()
	_round_left = ROUND_SECS


func _on_combo_banked(peer_id: int, points: float, _duration: float, _multiplier: int):
	if !multiplayer.is_server():
		return
	_round_points[peer_id] = _round_points.get(peer_id, 0.0) + points


#endregion


func _on_player_crashed(peer_id: int):
	if !multiplayer.is_server():
		return

	get_tree().create_timer(_respawn_delay).timeout.connect(
		func(): _respawn_at_crash_site(peer_id), CONNECT_ONE_SHOT
	)


## Free roam respawns you where you crashed (upright, same heading) rather than back at
## spawn. Delegates to the shared SpawnManager path so crash recovery and the R tap behave
## identically; that path doesn't touch the persistent respawn point, so the pause-menu
## respawn button still returns to the original spawn.
func _respawn_at_crash_site(peer_id: int):
	# Already recovered (e.g. pause-menu respawn button) before the timer fired — skip
	# so we don't respawn a second time.
	if not spawn_manager._get_player_by_peer_id(peer_id).is_crashed:
		return
	spawn_manager.respawn_in_place(peer_id)


func _on_player_latejoined(peer_id: int):
	gamemode_manager.latespawn_player(peer_id)


func _on_player_disconnected(peer_id: int):
	if gamemode_manager.match_state == GamemodeManager.MatchState.IN_GAME:
		spawn_manager.rpc_despawn_player.rpc(peer_id)


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if game_mode_event_hud_state == null:
		issues.append("game_mode_event_hud_state must not be empty")
	if level_manager == null:
		issues.append("level_manager must not be empty")
	if pickup_spawn_manager == null:
		issues.append("pickup_spawn_manager must not be empty")
	if trick_manager == null:
		issues.append("trick_manager must not be empty")
	if riding_hud_state == null:
		issues.append("riding_hud_state must not be empty")

	return issues
