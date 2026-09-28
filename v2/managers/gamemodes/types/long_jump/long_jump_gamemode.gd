@tool
## Trick long jump: after the grid + countdown runner, riders take LongJumpTask attempts for
## `duration_secs`; each rider's best attempt ranks them. The host ending it from pause still
## shows results.
class_name LongJumpGameMode extends RunnerGameMode

@export var trick_manager: TrickManager
@export var duration_secs: float = 180.0

var _jump_task: LongJumpTask
var _time_left: float = 0.0
var _refresh_accum: float = 0.0
## peer_id -> {"best": float, "last": float}
var _scores: Dictionary[int, Dictionary] = {}


func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.current_game_mode = GameModeType.Kind.LONG_JUMP
	DebugUtils.DebugMsg("Long Jump Mode")

	super(state_context)

	_scores.clear()
	_time_left = duration_secs
	_jump_task.attempt_scored.connect(_on_attempt_scored)
	if multiplayer.is_server():
		_start_next_runner()


func Update(delta: float):
	if !multiplayer.is_server():
		return
	if _active_runner != null and _is_last_runner():
		_time_left -= delta
		if _time_left <= 0.0:
			_end_session()
			return
		_refresh_accum -= delta
		if _refresh_accum <= 0.0:
			_refresh_accum = LeaderboardComponent.REFRESH_SECS
			_push_leaderboard()
	super(delta)


func Exit(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	_jump_task.attempt_scored.disconnect(_on_attempt_scored)
	_jump_task = null
	if multiplayer.is_server():
		riding_hud_state.clear_leaderboard()
	super(state_context)


#override
## Ending early still shows results, once the jumping has started.
func handle_cancel_event() -> bool:
	if _active_runner == null or !_is_last_runner():
		return false
	_end_session()
	return true


#override
func shows_step_count() -> bool:
	return false


#override
func _inject_runner_deps():
	super()
	_jump_task = _event.find_children("*", "LongJumpTask", true, false)[0]
	_jump_task.trick_manager = trick_manager


func _end_session():
	_stop_active_runner()
	riding_hud_state.clear_leaderboard()
	_show_results(_build_results())


func _on_attempt_scored(peer_id: int, points: float):
	var scores: Dictionary = _scores.get_or_add(peer_id, {"best": 0.0})
	scores["last"] = points
	scores["best"] = maxf(scores["best"], points)


func _best(peer_id: int) -> float:
	return _scores.get(peer_id, {}).get("best", 0.0)


func _ranked_peer_ids() -> Array:
	var peer_ids: Array = lobby_manager.lobby_players.keys()
	peer_ids.sort_custom(func(a, b): return _best(a) > _best(b))
	return peer_ids


func _push_leaderboard():
	var time_text := RaceTask.format_time_ms(int(_time_left * 1000.0))
	var rows: Array = []
	for peer_id in _ranked_peer_ids():
		var scores: Dictionary = _scores.get(peer_id, {})
		var cells := PackedStringArray(
			[
				lobby_manager.lobby_players[peer_id].username,
				"%d" % scores.get("best", 0.0),
				"%d" % scores["last"] if scores.has("last") else "—",
			]
		)
		rows.append({"peer_id": peer_id, "cells": cells})
		riding_hud_state.push_event_progress(peer_id, time_text)
	var headers := PackedStringArray(["", "🏆 %s" % tr("LB_BEST_LAP"), "🔁 %s" % tr("LB_LAST_LAP")])
	riding_hud_state.push_leaderboard(headers, rows, PackedInt32Array())


func _build_results() -> ResultsData:
	var rows: Array[Dictionary] = []
	for peer_id in _ranked_peer_ids():
		rows.append(
			{
				"Username": lobby_manager.lobby_players[peer_id].username,
				"Score": "%d" % _best(peer_id),
			}
		)
	return ResultsData.create(tr("LONG_JUMP_COMPLETE"), ["Username", "Score"], rows, ["", "🏆"])


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if trick_manager == null:
		issues.append("trick_manager must not be empty")
	return issues
