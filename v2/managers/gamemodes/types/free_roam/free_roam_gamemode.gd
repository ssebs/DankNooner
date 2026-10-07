@tool
class_name FreeRoamGameMode extends GameModeType

@export var game_mode_event_hud_state: GamemodeEventHUDState
@export var level_manager: LevelManager
## Optional — unlinked in main_game while traffic is disabled for perf; null skips traffic.
@export var npc_traffic_manager: NPCTrafficManager
@export var pickup_spawn_manager: PickupSpawnManager
@export var trick_manager: TrickManager
@export var riding_hud_state: RidingHUDState
@export var input_state_manager: InputStateManager
@export var hud_manager: HUDManager
@export var save_manager: SaveManager
@export var _respawn_delay: float = 2.5

## Trick round: banked combo points add up per human for ROUND_SECS, shown on the live
## leaderboard with the time left, then the winner is called out and it resets.
const ROUND_SECS: float = 60.0
const LEADERBOARD_REFRESH_SECS: float = 0.25

var _ctx: GamemodeStateContext
## The circle whose event picker is open — its events are what the picker indexes.
var _entered_circle: EventStartCircle
## The activity whose picker is open instead; null while a circle's is.
var _entered_activity: FreeRoamActivity
## peer_id -> points banked this round. Server only.
var _round_points: Dictionary[int, float] = {}
var _round_left: float = ROUND_SECS
var _leaderboard_refresh_accum: float = 0.0
## This client's running activity; null otherwise.
var _activity: FreeRoamActivity
## peer_id -> the activity they're running; also the one-rider-per-activity lock. Server only.
## Shared activities skip the lock.
var _running: Dictionary[int, FreeRoamActivity] = {}


#override
func is_late_joinable() -> bool:
	return true


#override
## Free roam's crash recovery is itself in place.
func respawns_crash_in_place(_peer_id: int) -> bool:
	return true


#override
## No lobby event to cancel here — only this rider's own activity.
func can_cancel_event() -> bool:
	return _activity != null


#override
## Leave the activity early with whatever result it has so far.
func handle_cancel_event() -> bool:
	_activity.finished.disconnect(_on_activity_finished)
	_activity.end()
	request_end_activity.rpc_id(1, _activity.get_result())
	_activity = null
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
	_signals_activities(true)

	# Hide + disable every event's objects (checkpoints, etc.) â€” they only show
	# while their own gamemode is running. Initial-load default and return path.
	for event_start_circle in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["EventCircles"]):
		(event_start_circle as EventStartCircle).set_active_event(null)

	# Only spawn if players aren't already in the level (e.g. coming from another gamemode)
	if spawn_manager.get_player_by_peer_id(multiplayer.get_unique_id()) == null:
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


## param is whether to connect() or disconnect()
func _signals_activities(should_connect: bool):
	for activity: FreeRoamActivity in get_tree().get_nodes_in_group(
		UtilsConstants.GROUPS["FreeRoamActivities"]
	):
		if should_connect:
			activity.entered_activity.connect(_on_activity_entered)
			activity.exited_activity.connect(_on_activity_exited)
		else:
			activity.entered_activity.disconnect(_on_activity_entered)
			activity.exited_activity.disconnect(_on_activity_exited)


func _on_event_circle_entered(peer_id: int, source_circle: EventStartCircle):
	# Every peer sees every rider's body enter; only the rider's own peer opens their picker, so
	# _entered_circle (which the submit indexes) is always this peer's.
	if peer_id != multiplayer.get_unique_id():
		return
	DebugUtils.DebugMsg("%d entered eventcircle: %s" % [peer_id, source_circle.name])

	_entered_circle = source_circle
	_entered_activity = null
	var names := PackedStringArray()
	var descriptions := PackedStringArray()
	# Time attack events' personal-best save keys, "" for the rest.
	var pb_keys := PackedStringArray()
	for event in source_circle.get_events():
		names.append(event.definition.name)
		descriptions.append(event.definition.description)
		var is_time_attack := event.definition.target_gamemode == GameModeType.Kind.TIME_ATTACK
		pb_keys.append(
			TimeAttackComponent.event_key(gamemode_manager.current_level_name, event)
			if is_time_attack else ""
		)

	_open_event_picker(peer_id, names, descriptions, pb_keys, false)

	# TODO - set player velocity to 0


func _on_event_circle_exited(peer_id: int, source_circle: EventStartCircle):
	# Quitting tears this mode out of the tree before the level, whose circles then report the
	# riders leaving — nothing to close, so the skip is intentional.
	if !is_inside_tree():
		return
	if peer_id != multiplayer.get_unique_id():
		return
	DebugUtils.DebugMsg("%d exited eventcircle: %s" % [peer_id, source_circle.name])
	_close_event_picker(peer_id)


func _open_event_picker(
	peer_id: int,
	names: PackedStringArray,
	descriptions: PackedStringArray,
	pb_keys: PackedStringArray,
	per_rider: bool
):
	game_mode_event_hud_state.on_player_entered_circle.rpc_id(
		1, peer_id, names, descriptions, pb_keys, per_rider
	)

	# connect hud signals
	if not game_mode_event_hud_state.hud_submitted.is_connected(
		_on_game_mode_event_confirm_hud_submitted
	):
		game_mode_event_hud_state.hud_submitted.connect(_on_game_mode_event_confirm_hud_submitted)


func _close_event_picker(peer_id: int):
	if game_mode_event_hud_state.hud_submitted.is_connected(
		_on_game_mode_event_confirm_hud_submitted
	):
		game_mode_event_hud_state.hud_submitted.disconnect(
			_on_game_mode_event_confirm_hud_submitted
		)

	game_mode_event_hud_state.on_player_close_pressed.rpc_id(1, peer_id)


func _on_game_mode_event_confirm_hud_submitted(peer_id: int, event_index: int):
	DebugUtils.DebugMsg("Starting Event... %d" % peer_id)
	game_mode_event_hud_state.on_player_close_pressed.rpc_id(1, peer_id)
	# Per rider: only the submitter runs it, the lobby stays in free roam.
	if _entered_activity != null:
		if save_manager.get_player_definition().money < _entered_activity.price:
			riding_hud_state.flash_money()
			return
		request_start_activity.rpc_id(1, _entered_activity.get_path())
		return
	var event := _entered_circle.get_events()[event_index]
	var target := event.definition.target_gamemode
	if event.definition.fuel_up_first:
		target = GameModeType.Kind.FUEL_UP
	gamemode_manager.change_gamemode.rpc_id(1, target, peer_id, event.get_path())


func Exit(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.player_crashed.disconnect(_on_player_crashed)
	gamemode_manager.player_disconnected.disconnect(_on_player_disconnected)
	gamemode_manager.player_latejoined.disconnect(_on_player_latejoined)
	trick_manager.combo_banked.disconnect(_on_combo_banked)

	_signals_event_circles(false)
	_signals_activities(false)

	# Host started an event mid-activity — that event places and freezes riders itself.
	if _activity != null:
		_activity.finished.disconnect(_on_activity_finished)
		_activity.end()
		_activity = null

	if multiplayer.is_server():
		for peer_id in _running:
			_running[peer_id].server_end(peer_id, 0.0, spawn_manager)
		_running.clear()
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
		if spawn_manager.get_player_by_peer_id(peer_id) != null:
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

#region Activities (per rider)


func _on_activity_entered(peer_id: int, activity: FreeRoamActivity):
	# Same local-only rule as circles. Also skips a rider their own activity parked in its circle.
	if peer_id != multiplayer.get_unique_id() or _activity != null:
		return
	_entered_circle = null
	_entered_activity = activity
	_open_event_picker(
		peer_id,
		PackedStringArray([activity.event_name]),
		PackedStringArray([activity.event_description]),
		PackedStringArray([""]),
		true
	)


func _on_activity_exited(peer_id: int, _exited: FreeRoamActivity):
	# Quitting mid-activity: see _on_event_circle_exited.
	if !is_inside_tree():
		return
	if peer_id != multiplayer.get_unique_id() or _activity != null:
		return
	_close_event_picker(peer_id)


## Client-callable: start `activity_path` for YOU. The server derives the rider from the sender.
@rpc("any_peer", "call_local", "reliable")
func request_start_activity(activity_path: NodePath):
	if !multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender > 1 else 1
	var activity := get_node(activity_path) as FreeRoamActivity
	# The host started an event while this was in flight, the rider's busy, or someone's on it.
	if (
		gamemode_manager.get_current_gamemode() != self
		or _running.has(peer_id)
		or (!activity.is_shared() and activity in _running.values())
		or spawn_manager.get_player_by_peer_id(peer_id).is_crashed
	):
		return
	_running[peer_id] = activity
	# Sent before server_start (reliable RPCs arrive in order), so the client is already listening
	# for whatever server_start triggers, e.g. the fuel-up teleport.
	_rpc_begin_activity.rpc_id(peer_id, activity_path)
	activity.server_start(peer_id, spawn_manager)


## Client-callable: end YOUR activity with `result`, finished or cancelled.
@rpc("any_peer", "call_local", "reliable")
func request_end_activity(result: float):
	if !multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender > 1 else 1
	# Exit already ended everyone's before this arrived.
	if !_running.has(peer_id):
		return
	_running[peer_id].server_end(peer_id, result, spawn_manager)
	_running.erase(peer_id)


## Server → the rider's own client.
@rpc("call_local", "reliable")
func _rpc_begin_activity(activity_path: NodePath):
	_activity = get_node(activity_path)
	# Affordable — checked when the picker was submitted.
	save_manager.spend(_activity.price)
	_activity.finished.connect(_on_activity_finished, CONNECT_ONE_SHOT)
	_activity.begin(
		spawn_manager.get_player_by_peer_id(multiplayer.get_unique_id()),
		input_state_manager,
		gamemode_manager.audio_manager,
		hud_manager
	)


## Local — the activity already handed the rider back.
func _on_activity_finished():
	request_end_activity.rpc_id(1, _activity.get_result())
	_activity = null


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
	if not spawn_manager.get_player_by_peer_id(peer_id).is_crashed:
		return
	spawn_manager.respawn_in_place(peer_id)


func _on_player_latejoined(peer_id: int):
	gamemode_manager.latespawn_player(peer_id)


func _on_player_disconnected(peer_id: int):
	if gamemode_manager.match_state == GamemodeManager.MatchState.IN_GAME:
		spawn_manager.rpc_despawn_player.rpc(peer_id)
	_running.erase(peer_id)


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
	if input_state_manager == null:
		issues.append("input_state_manager must not be empty")
	if hud_manager == null:
		issues.append("hud_manager must not be empty")
	if save_manager == null:
		issues.append("save_manager must not be empty")

	return issues
