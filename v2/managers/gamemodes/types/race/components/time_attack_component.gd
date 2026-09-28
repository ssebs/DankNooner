@tool
## Endless laps against the clock (RaceTask.endless). Full boost at the start, session lap times on
## the host (best lap is the TIME_ATTACK standing), and each lap sent to its rider, whose client
## saves it if it beats their personal best. Point-to-point riders get a run-again prompt per run.
class_name TimeAttackComponent extends RaceComponent

@export var save_manager: SaveManager

## "<level>/<event>" -> peer_id -> {"best_lap_ms": int, "last_lap_ms": int}. Kept for the
## whole host session so re-entries compete against earlier laps.
var _session_times: Dictionary[String, Dictionary] = {}


func race_start() -> void:
	for peer_id in race_mode.lobby_manager.lobby_players:
		# Player may not be spawned yet (late-join) — skip is intentional.
		if race_mode.spawn_manager._get_player_by_peer_id(peer_id) != null:
			race_mode.spawn_manager.max_boost_player.rpc(peer_id)
	race_mode.race_task.lap_completed.connect(_on_lap_completed)


func race_end() -> void:
	race_mode.race_task.lap_completed.disconnect(_on_lap_completed)


func best_lap_ms(peer_id: int) -> float:
	return _times(peer_id).get("best_lap_ms", INF)


func column_headers() -> PackedStringArray:
	return PackedStringArray(["🏆", "🔁", "⏱"])


func column_cells(peer_id: int) -> PackedStringArray:
	var times := _times(peer_id)
	var current_ms := -1
	if race_mode.race_task.has_racer(peer_id):
		current_ms = race_mode.race_task.get_lap_elapsed_ms(peer_id)
	return PackedStringArray([
		_time_text(times.get("best_lap_ms", -1)),
		_time_text(times.get("last_lap_ms", -1)),
		_time_text(current_ms),
	])


## Client-callable: the finish prompt's "run again".
@rpc("any_peer", "call_local", "reliable")
func request_retry() -> void:
	if !multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender > 1 else 1
	# The host may have ended the event before the request arrived — skip is intentional.
	if race_mode.race_task == null or !race_mode.race_task.has_racer(peer_id):
		return
	race_mode.race_task.retry_run(peer_id)


func _on_lap_completed(peer_id: int, lap_ms: int) -> void:
	var times := _times(peer_id)
	times["last_lap_ms"] = lap_ms
	times["best_lap_ms"] = mini(times.get("best_lap_ms", lap_ms), lap_ms)
	_rpc_save_personal_best.rpc_id(peer_id, _event_key(), lap_ms)
	if race_mode.race_task.is_point_to_point():
		race_mode.tutorial_hud.rpc_update_progress.rpc_id(peer_id, tr("TIME_ATTACK_RUN_DONE"))
		race_mode.results_hud.rpc_show_run_finished.rpc_id(
			peer_id, race_mode.leaderboard.build_results().to_dict()
		)


func _times(peer_id: int) -> Dictionary:
	return _session_times.get_or_add(_event_key(), {}).get_or_add(peer_id, {})


## Same on every peer — gamemode_manager syncs the level and event.
func _event_key() -> String:
	var gm := race_mode.gamemode_manager
	return "%s/%s" % [LevelManager.LevelName.find_key(gm.current_level_name), gm.current_event.name]


func _time_text(ms: int) -> String:
	return RaceTask.format_time_ms(ms) if ms >= 0 else "—"


@rpc("call_local", "reliable")
func _rpc_save_personal_best(event_key: String, lap_ms: int) -> void:
	var progression: Dictionary = save_manager.current_save["progression"]
	var pbs: Dictionary = progression["time_attack"].get_or_add(event_key, {})
	if pbs.has("best_lap_ms") and pbs["best_lap_ms"] <= lap_ms:
		return
	pbs["best_lap_ms"] = lap_ms
	save_manager.update_save("progression", progression, false, true)
	DebugUtils.DebugMsg("TimeAttack: new PB %s = %s" % [event_key, RaceTask.format_time_ms(lap_ms)])


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if save_manager == null:
		issues.append("save_manager must not be empty")
	return issues
