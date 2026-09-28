@tool
## Endless laps against the clock (RaceTask.endless). Full boost at the start, session lap times on
## the host (best lap is the TIME_ATTACK standing), and each lap sent to its rider, whose client
## saves it if it beats their personal best. Point-to-point riders get a run-again prompt per run.
class_name TimeAttackComponent extends RaceComponent

@export var save_manager: SaveManager

## event_key -> peer_id -> {"best_lap_ms": int, "last_lap_ms": int}. Kept for the
## whole host session so re-entries compete against earlier laps.
var _session_times: Dictionary[String, Dictionary] = {}


## Save key for an event's personal best — "<level>/<circle>/<event>". Event names repeat
## across a level's circles, so the circle is part of the key.
static func event_key(level_name: LevelManager.LevelName, event: GameModeEvent) -> String:
	return "%s/%s/%s" % [
		LevelManager.LevelName.find_key(level_name), event.get_circle().name, event.name
	]


## This client's saved best lap for `key`, -1 if none.
static func personal_best_ms(save: SaveManager, key: String) -> int:
	var pbs: Dictionary = save.current_save["progression"]["time_attack"].get(key, {})
	return int(pbs.get("best_lap_ms", -1))


## "PB 0:38.50", or the no-PB-yet text.
static func personal_best_text(save: SaveManager, key: String) -> String:
	var ms := personal_best_ms(save, key)
	if ms < 0:
		return TranslationServer.translate("TIME_ATTACK_NO_PB")
	return TranslationServer.translate("TIME_ATTACK_PB").format({"time": RaceTask.format_time_ms(ms)})


func race_start() -> void:
	# Every run starts on a full boost meter — restart_run refills it too.
	for peer_id in race_mode.lobby_manager.lobby_players:
		# Player may not be spawned yet (late-join) — skip is intentional.
		if race_mode.spawn_manager._get_player_by_peer_id(peer_id) != null:
			race_mode.spawn_manager.max_boost_player.rpc(peer_id)
	race_mode.race_task.lap_completed.connect(_on_lap_completed)
	_rpc_show_personal_best.rpc(_event_key())


func race_end() -> void:
	race_mode.race_task.lap_completed.disconnect(_on_lap_completed)


func best_lap_ms(peer_id: int) -> float:
	return _times(peer_id).get("best_lap_ms", INF)


func column_headers() -> PackedStringArray:
	return PackedStringArray([
		"🏆 %s" % tr("LB_BEST_LAP"), "🔁 %s" % tr("LB_LAST_LAP"), "⏱ %s" % tr("LB_CURRENT_LAP")
	])


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
	restart_run(peer_id)


## A fresh run for one rider: grid, 3-2-1, full boost. Hold-R respawn and "run again".
func restart_run(peer_id: int) -> void:
	race_mode.race_task.restart_run(peer_id)
	race_mode.spawn_manager.max_boost_player.rpc(peer_id)


func _on_lap_completed(peer_id: int, lap_ms: int) -> void:
	var times := _times(peer_id)
	times["last_lap_ms"] = lap_ms
	times["best_lap_ms"] = mini(times.get("best_lap_ms", lap_ms), lap_ms)
	_rpc_save_personal_best.rpc_id(peer_id, _event_key(), lap_ms)
	if race_mode.race_task.is_point_to_point():
		race_mode.riding_hud_state.push_event_status(peer_id, "TIME_ATTACK_RUN_DONE")
		race_mode.results_hud.rpc_show_run_finished.rpc_id(
			peer_id, race_mode.leaderboard.build_results().to_dict()
		)


func _times(peer_id: int) -> Dictionary:
	return _session_times.get_or_add(_event_key(), {}).get_or_add(peer_id, {})


func _event_key() -> String:
	var gm := race_mode.gamemode_manager
	return event_key(gm.current_level_name, gm.current_event)


func _time_text(ms: int) -> String:
	return RaceTask.format_time_ms(ms) if ms >= 0 else "—"


@rpc("call_local", "reliable")
func _rpc_show_personal_best(key: String) -> void:
	race_mode.riding_hud_state.set_race_pb(personal_best_text(save_manager, key))


@rpc("call_local", "reliable")
func _rpc_save_personal_best(key: String, lap_ms: int) -> void:
	var pb_ms := personal_best_ms(save_manager, key)
	if pb_ms >= 0 and pb_ms <= lap_ms:
		return
	var progression: Dictionary = save_manager.current_save["progression"]
	progression["time_attack"][key] = {"best_lap_ms": lap_ms}
	save_manager.update_save("progression", progression, false, true)
	race_mode.riding_hud_state.set_race_pb(personal_best_text(save_manager, key))


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if save_manager == null:
		issues.append("save_manager must not be empty")
	return issues
