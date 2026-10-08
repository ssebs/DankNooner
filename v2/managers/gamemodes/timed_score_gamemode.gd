@tool
## Base for modes that score riders over a timed session: after the grid + countdown runner, the
## last runner runs for `duration_secs`. Owns the clock, the live leaderboard cadence and the
## results (timeout, or the host's Cancel Event). Subclasses define the score and the columns.
class_name TimedScoreGameMode extends RunnerGameMode

@export var trick_manager: TrickManager
@export var duration_secs: float = 180.0

var _time_left: float = 0.0
var _refresh_accum: float = 0.0
## The host ended the session early — riders return to their respawn point, not the level grid.
var _cancelled: bool = false


func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	super(state_context)

	_time_left = duration_secs
	_cancelled = false
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
			var time_text := RaceTask.format_time_ms(int(_time_left * 1000.0))
			for peer_id in lobby_manager.lobby_players:
				riding_hud_state.push_event_progress(peer_id, time_text)
			_push_leaderboard()
	super(delta)


func Exit(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	if multiplayer.is_server():
		riding_hud_state.clear_leaderboard()
	super(state_context)


#override
## Ending early still shows results, once the session has started.
func handle_cancel_event() -> bool:
	if _active_runner == null or !_is_last_runner():
		return false
	_cancelled = true
	_end_session()
	return true


#override
func _return_spawn() -> GamemodeStateContext.ReturnSpawn:
	if _cancelled:
		return GamemodeStateContext.ReturnSpawn.RESPAWN_POINT
	return super()


#override
func shows_step_count() -> bool:
	return false


## Override: the peer's standing. Results rank by it, highest first.
func _score(_peer_id: int) -> float:
	return 0.0


#override
func _is_score_mode() -> bool:
	return true


#override
func _payout_score(peer_id: int) -> float:
	return _score(peer_id)


## Override: localization key of the results title.
func _results_title_key() -> String:
	return ""


## Override: push the live leaderboard (the clock is already on the progress line).
func _push_leaderboard():
	pass


## The last runner's riders only — late joiners never played it.
func _ranked_peer_ids() -> Array:
	var peer_ids: Array = _active_runner.player_states.keys()
	peer_ids.sort_custom(func(a, b): return _score(a) > _score(b))
	return peer_ids


func _end_session():
	# Before stop() — it clears the runner's player_states that results rank.
	var results := _build_results()
	_stop_active_runner()
	riding_hud_state.clear_leaderboard()
	_show_results(results)


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
				}
			)
		)
	return ResultsData.create(tr(_results_title_key()), ["Username", "Score"], rows, ["", "🏆"])


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if trick_manager == null:
		issues.append("trick_manager must not be empty")
	return issues
