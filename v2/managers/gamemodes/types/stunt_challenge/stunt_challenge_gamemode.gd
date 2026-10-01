@tool
## Trick-sequence race. The event's last runner is a SequentialTaskRunner of PerformTrickTasks (tree
## order = sequence), after a grid + countdown runner. Live leaderboard by progress (tricks done,
## then time); results by that runner's completion time, fastest first.
class_name StuntChallengeGameMode extends RunnerGameMode

var _refresh_accum: float = 0.0


func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.current_game_mode = GameModeType.Kind.STUNT_CHALLENGE
	DebugUtils.DebugMsg("Stunt Challenge Mode")

	super(state_context)

	if multiplayer.is_server():
		_start_next_runner()


func Update(delta: float):
	if !multiplayer.is_server():
		return
	if _active_runner != null and _is_last_runner():
		_refresh_accum -= delta
		if _refresh_accum <= 0.0:
			_refresh_accum = LeaderboardComponent.REFRESH_SECS
			_push_leaderboard(_active_runner)
	super(delta)


func Exit(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	if multiplayer.is_server():
		riding_hud_state.clear_leaderboard()
	super(state_context)


func _push_leaderboard(runner: TaskRunner):
	var states: Dictionary = runner.player_states
	var peer_ids: Array = states.keys()
	peer_ids.sort_custom(func(a, b): return _ranks_before(states[a], states[b]))
	var total: int = runner.tasks.size()
	var now := Time.get_ticks_msec() as float
	var rows: Array = []
	for peer_id in peer_ids:
		var state: PlayerTaskState = states[peer_id]
		var time_ms := state.completion_time_ms if state.completed else now - state.start_time
		var cells := PackedStringArray(
			[
				lobby_manager.lobby_players[peer_id].username,
				"%d/%d" % [state.current_index, total],
				"%.1fs" % (time_ms / 1000.0),
			]
		)
		rows.append({"peer_id": peer_id, "cells": cells})
	var headers := PackedStringArray(["", "🎯 %s" % tr("LB_TRICKS"), "⏱ %s" % tr("LB_TIME")])
	riding_hud_state.push_leaderboard(headers, rows, PackedInt32Array())


## More tricks done first; among finishers, the faster time.
func _ranks_before(a: PlayerTaskState, b: PlayerTaskState) -> bool:
	if a.current_index != b.current_index:
		return a.current_index > b.current_index
	return a.completion_time_ms < b.completion_time_ms


#override
func _on_last_runner_completed(runner: TaskRunner):
	riding_hud_state.clear_leaderboard()
	_show_results(_completion_results(runner, "CHALLENGE_COMPLETE"))
