@tool
## The live leaderboard (humans, riding HUD) and the results table (humans + NPCs). Columns: name,
## race position, score (STUNT_RACE), then every component's column_headers. Standing is fixed by
## race_type: STUNT_RACE by RaceGameMode.score, TIME_ATTACK by session best lap, otherwise race
## position.
class_name LeaderboardComponent extends RaceComponent

## Cadence for pushing the live leaderboard to clients (a few Hz — the values crawl).
const REFRESH_SECS: float = 0.25
## Puts every NPC row below every human when standing is by score (humans sort by -score).
const NPC_SORT_OFFSET: float = 1e12

var _refresh_accum: float = 0.0


func tick(delta: float) -> void:
	_refresh_accum -= delta
	if _refresh_accum > 0.0:
		return
	_refresh_accum = REFRESH_SECS
	var peer_ids: Array[int] = []
	for peer_id in race_mode.lobby_manager.lobby_players:
		# Player may not be spawned yet (late-join) — skip is intentional.
		if race_mode.spawn_manager._get_player_by_peer_id(peer_id) != null:
			peer_ids.append(peer_id)
	peer_ids.sort_custom(func(a, b): return _human_sort_key(a) < _human_sort_key(b))
	var rows: Array = []
	for peer_id in peer_ids:
		rows.append({"peer_id": peer_id, "cells": _human_cells(peer_id)})
	var tricks := PackedInt32Array()
	if race_mode.challenges != null:
		tricks = race_mode.challenges.hint_tricks()
	race_mode.riding_hud_state.push_leaderboard(_headers(), rows, tricks)


func race_end() -> void:
	race_mode.riding_hud_state.clear_leaderboard()


## Rebuilt live on every refresh — bots keep racing through the results countdown, so one that
## finishes mid-countdown gets its real time instead of a DNF. Same columns as the leaderboard,
## plus the finish time (TIME_ATTACK never finishes — its lap columns replace it).
func build_results() -> ResultsData:
	var race_task := race_mode.race_task
	var rows: Array[Dictionary] = []
	for peer_id in race_mode.lobby_manager.lobby_players:
		# Late joiners never raced, and an unspawned player has no position — skip is intentional.
		var player := race_mode.spawn_manager._get_player_by_peer_id(peer_id)
		if player == null or !race_task.has_racer(peer_id):
			continue
		rows.append(_result_row(peer_id, _human_cells(peer_id), _human_sort_key(peer_id)))
	if race_mode.npc_racers != null:
		for npc in race_mode.npc_racers.get_npcs():
			var npc_id := int(npc.name)
			var cells := PackedStringArray([npc.username, _place_text(npc_id)])
			# NPCs don't score — blank the rest of the columns.
			cells.resize(_headers().size())
			var sort_key: float = race_task.get_race_position(npc_id)
			if _by_score():
				sort_key += NPC_SORT_OFFSET
			rows.append(_result_row(npc_id, cells, sort_key))
	rows.sort_custom(func(a, b): return a["_sort_key"] < b["_sort_key"])

	var headers: Array[String] = []
	headers.assign(_headers())
	var title := tr("TIME_ATTACK_RUN_COMPLETE")
	if !_is_time_attack():
		headers.insert(1, "⏱ %s" % tr("LB_TIME"))
		title = tr("RACE_COMPLETE")
	var columns: Array[String] = []
	for i in headers.size():
		columns.append(str(i))
	return ResultsData.create(title, columns, rows, headers)


func _by_score() -> bool:
	return race_mode.race_type == RaceGameMode.RaceType.STUNT_RACE


func _is_time_attack() -> bool:
	return race_mode.race_type == RaceGameMode.RaceType.TIME_ATTACK


func _headers() -> PackedStringArray:
	var headers := PackedStringArray(["", "🏁 %s" % tr("LB_PLACE")])
	if _by_score():
		headers.append("💰 %s" % tr("LB_SCORE"))
	for component in race_mode.get_components():
		headers.append_array(component.column_headers())
	return headers


func _human_cells(peer_id: int) -> PackedStringArray:
	var username: String = race_mode.lobby_manager.lobby_players[peer_id].username
	var cells := PackedStringArray([username, _place_text(peer_id)])
	if _by_score():
		cells.append("%d" % int(race_mode.score(peer_id)))
	for component in race_mode.get_components():
		cells.append_array(component.column_cells(peer_id))
	return cells


func _human_sort_key(peer_id: int) -> float:
	if _by_score():
		return -race_mode.score(peer_id)
	if _is_time_attack():
		return race_mode.time_attack.best_lap_ms(peer_id)
	# Not in the race body yet (grid/countdown) — no position, sorts last.
	if !race_mode.race_task.has_racer(peer_id):
		return INF
	return race_mode.race_task.get_race_position(peer_id)


func _place_text(racer_id: int) -> String:
	if !race_mode.race_task.has_racer(racer_id):
		return "—"
	return "P%d" % race_mode.race_task.get_race_position(racer_id)


## cells keyed by column index, with the finish time spliced in after the name.
func _result_row(racer_id: int, cells: PackedStringArray, sort_key: float) -> Dictionary:
	if !_is_time_attack():
		var time_ms := race_mode.race_task.get_completion_time_ms(racer_id)
		cells.insert(1, "%.1fs" % (time_ms / 1000.0) if time_ms >= 0.0 else tr("RACE_RACING"))
	var row := {"_peer_id": racer_id, "_sort_key": sort_key}
	for i in cells.size():
		row[str(i)] = cells[i]
	return row
