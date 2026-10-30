@tool
## Crash launch: `heat_count` heats of everyone at once, from a side-by-side grid into a low wall.
## The event's runner (grid + countdown + CrashLaunchTask) reruns per heat. A rider's heat counts
## its first measured wall crash; any other crash respawns them on their grid slot to go again. A
## crashed rider respawns once their body stops, the crash timer being the cap. A heat ends once
## every rider has launched, or at `heat_timeout_secs`. Score: distance plus heat
## placement points, summed over the heats, plus a bonus for the match's longest launch.
class_name CrashLaunchGameMode extends RunnerGameMode

@export var heat_count: int = 3
## From the grid, countdown included. Riders who haven't launched by then score nothing that heat.
@export var heat_timeout_secs: float = 45.0
@export var points_per_meter: float = 10.0
## Heat points by distance rank; 0 past the end.
@export var placement_points: PackedInt32Array = PackedInt32Array([300, 200, 150, 100, 50])
@export var longest_launch_bonus: int = 500

var _heat: int = 0
var _heat_time_left: float = 0.0
var _refresh_accum: float = 0.0
## peer_id -> this heat's launch (m).
var _heat_launches: Dictionary[int, float] = {}
## peer_id -> {"points": float, "best": float}, over every heat so far.
var _totals: Dictionary[int, Dictionary] = {}


func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.current_game_mode = GameModeType.Kind.CRASH_LAUNCH
	DebugUtils.DebugMsg("Crash Launch Mode")

	super(state_context)

	_heat = 0
	_totals.clear()
	gamemode_manager.player_launch_measured.connect(_on_player_launch_measured)
	if multiplayer.is_server():
		_start_heat()


func Update(delta: float):
	if !multiplayer.is_server():
		return
	if _active_runner != null:
		_heat_time_left -= delta
		if _heat_time_left <= 0.0:
			_end_heat()
			return
		_refresh_accum -= delta
		if _refresh_accum <= 0.0:
			_refresh_accum = LeaderboardComponent.REFRESH_SECS
			_push_progress()
			_push_leaderboard()
	super(delta)


func Exit(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.player_launch_measured.disconnect(_on_player_launch_measured)
	if multiplayer.is_server():
		riding_hud_state.clear_leaderboard()
	super(state_context)


#override
func shows_step_count() -> bool:
	return false


#region Heats


func _start_heat():
	_heat += 1
	_heat_time_left = heat_timeout_secs
	_heat_launches.clear()
	_active_runner_index = -1
	_start_next_runner()
	for peer_id in _active_runner.player_states:
		_totals.get_or_add(peer_id, {"points": 0.0, "best": 0.0})


## Scores the heat, then starts the next one or shows results.
func _end_heat():
	_stop_active_runner()
	var ranked := _heat_launches.keys()
	ranked.sort_custom(func(a, b): return _heat_launches[a] > _heat_launches[b])
	for place in ranked.size():
		var peer_id: int = ranked[place]
		var meters := _heat_launches[peer_id]
		var totals := _totals[peer_id]
		totals["points"] += meters * points_per_meter
		if place < placement_points.size():
			totals["points"] += placement_points[place]
		totals["best"] = maxf(totals["best"], meters)

	if _heat < heat_count:
		_start_heat()
		return
	var longest := _longest_launcher()
	if longest != -1:
		_totals[longest]["points"] += longest_launch_bonus
	riding_hud_state.clear_leaderboard()
	_show_results(_build_results())


## The match's longest launch, -1 if nobody launched.
func _longest_launcher() -> int:
	var longest := -1
	var longest_m := 0.0
	for peer_id in _totals:
		if _totals[peer_id]["best"] > longest_m:
			longest = peer_id
			longest_m = _totals[peer_id]["best"]
	return longest


func _is_launching(peer_id: int) -> bool:
	var runner := _active_runner as SequentialTaskRunner
	return runner.get_current_task(peer_id) is CrashLaunchTask


#endregion

#region Scoring + HUD


func _score(peer_id: int) -> float:
	return _totals[peer_id]["points"]


#override
func _is_score_mode() -> bool:
	return true


#override
func _payout_score(peer_id: int) -> float:
	return _score(peer_id)


func _ranked_peer_ids() -> Array:
	var peer_ids := _totals.keys()
	peer_ids.sort_custom(func(a, b): return _score(a) > _score(b))
	return peer_ids


## Heat number and time left, once the countdown has handed over to the launch.
func _push_progress():
	var text := "%s  %s" % [
		tr("CRASH_LAUNCH_HEAT") % [_heat, heat_count],
		RaceTask.format_time_ms(int(_heat_time_left * 1000.0)),
	]
	for peer_id in _active_runner.player_states:
		if _is_launching(peer_id):
			riding_hud_state.push_event_progress(peer_id, text)


func _push_leaderboard():
	var rows: Array = []
	for peer_id in _ranked_peer_ids():
		var cells := PackedStringArray(
			[
				lobby_manager.lobby_players[peer_id].username,
				"%d" % _score(peer_id),
				"%dm" % _heat_launches[peer_id] if _heat_launches.has(peer_id) else "—",
			]
		)
		rows.append({"peer_id": peer_id, "cells": cells})
	var headers := PackedStringArray(["", "🏆 %s" % tr("LB_SCORE"), "💥 %s" % tr("LB_HEAT")])
	riding_hud_state.push_leaderboard(headers, rows, PackedInt32Array())


func _build_results() -> ResultsData:
	var rows: Array[Dictionary] = []
	for peer_id in _ranked_peer_ids():
		(
			rows
			. append(
				{
					"_peer_id": peer_id,
					"Username": lobby_manager.lobby_players[peer_id].username,
					"Score": "%d" % _score(peer_id),
					"Best": "%dm" % _totals[peer_id]["best"],
				}
			)
		)
	return ResultsData.create(
		tr("CRASH_LAUNCH_COMPLETE"),
		["Username", "Score", "Best"],
		rows,
		["", "🏆", "📏 %s" % tr("LB_BEST_LAP")]
	)


#endregion

#region Handlers


func _on_player_launch_measured(peer_id: int, meters: float):
	# A body settling after the last heat, under the results — skip is intentional
	if _active_runner == null:
		return
	# Late joiners free-roam outside the runner — skip is intentional
	if !_active_runner.player_states.has(peer_id):
		return
	# The body came to rest: respawn now rather than waiting out the crash timer (the cap).
	_respawn_crashed_player(peer_id, respawns_crash_in_place(peer_id))
	# Only the first wall crash of the launch step counts; other crashes just respawn for another go.
	var is_wall := (
		spawn_manager.get_player_by_peer_id(peer_id).crash_type == CrashController.CrashType.WALL
	)
	if !is_wall or !_is_launching(peer_id) or _heat_launches.has(peer_id):
		return
	_heat_launches[peer_id] = meters
	if _heat_launches.size() == _active_runner.player_states.size():
		_end_heat()


#override
func _on_player_disconnected(peer_id: int):
	super(peer_id)
	_totals.erase(peer_id)
	_heat_launches.erase(peer_id)


#endregion
