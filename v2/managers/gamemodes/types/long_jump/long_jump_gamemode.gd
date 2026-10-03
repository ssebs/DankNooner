@tool
## Trick long jump: after the grid + countdown runner, riders take LongJumpTask attempts for
## `duration_secs`; each rider's best attempt ranks them. The host ending it from pause still
## shows results.
class_name LongJumpGameMode extends TimedScoreGameMode

var _jump_task: LongJumpTask
## peer_id -> {"best": float, "last": float}
var _scores: Dictionary[int, Dictionary] = {}


func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.current_game_mode = GameModeType.Kind.LONG_JUMP
	DebugUtils.DebugMsg("Long Jump Mode")

	super(state_context)

	_scores.clear()
	_jump_task.attempt_scored.connect(_on_attempt_scored)


func Exit(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	_jump_task.attempt_scored.disconnect(_on_attempt_scored)
	_jump_task = null
	super(state_context)


#override
func _inject_runner_deps():
	super()
	_jump_task = _event.find_children("*", "LongJumpTask", true, false)[0]
	_jump_task.trick_manager = trick_manager


func _on_attempt_scored(peer_id: int, points: float):
	var scores: Dictionary = _scores.get_or_add(peer_id, {"best": 0.0})
	scores["last"] = points
	scores["best"] = maxf(scores["best"], points)


#override
func _score(peer_id: int) -> float:
	return _scores.get(peer_id, {}).get("best", 0.0)


#override
func _results_title_key() -> String:
	return "LONG_JUMP_COMPLETE"


#override
func _push_leaderboard():
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
	var headers := PackedStringArray(["", "🏆 %s" % tr("LB_BEST_LAP"), "🔁 %s" % tr("LB_LAST_LAP")])
	riding_hud_state.push_leaderboard(headers, rows, PackedInt32Array())
