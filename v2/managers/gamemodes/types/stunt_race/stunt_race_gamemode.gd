@tool
## Point-to-point stunt race: a station-to-station checkpoint race. Same runner/task/RaceTask
## setup as RoadRaceGameMode — the leg route is authored under the EventStartCircle in the level
## (GridSpawnTask -> CountdownTask -> RaceTask with the station gates as checkpoints; total_laps=1
## for a straight A->B->C). Duplicated from RoadRaceGameMode rather than subclassing it: the stunt
## race is expected to diverge (style + knockout scoring, boost=fuel, items), so it's kept
## independently editable. See planning_docs/StuntRaceGamemode.md.
class_name StuntRaceGameMode extends GameModeType

@export var tutorial_hud: TutorialHUDState
@export var results_hud: ResultsHUDState
@export var input_state_manager: InputStateManager
@export var lobby_manager: LobbyManager
@export var menu_manager: MenuManager
@export var audio_manager: AudioManager
@export var npc_race_manager: NPCRaceManager
@export var riding_hud_state: RidingHUDState
@export var trick_manager: TrickManager
@export var _respawn_delay: float = 2.5
## When true, finishing the race teleports everyone back to the grid; otherwise they stay
## where they finished and only the results HUD closes.
@export var teleport_to_start_on_finish: bool = false
## Score awarded by finish order among humans (NPCs ignored); 0 past the end.
@export var placement_points: PackedInt32Array = PackedInt32Array([300, 200, 150, 100, 50])


const RESULTS_REFRESH_SECS: float = 1.0
## Cadence for pushing the live leaderboard to clients (a few Hz — the values crawl).
const LEADERBOARD_REFRESH_SECS: float = 0.25
## Results sort key offset that puts every NPC row below every human (humans sort by -score).
const NPC_SORT_OFFSET: float = 1e12

var _start_circle: EventStartCircle
## A stunt track authors a StuntRaceTask (RaceTask + item spawners) in place of a plain RaceTask.
var _race_task: RaceTask
var _runners: Array[TaskRunner] = []
var _active_runner: TaskRunner
var _active_runner_index: int = -1
var _results_countdown: float = -1.0
var _results_countdown_total: float = 10.0
## Human rows cached at the all-finished snapshot — the runner clears its state on
## stop(), so they can't be re-derived. NPC rows re-derive live from RaceTask.
var _human_rows: Array[Dictionary] = []
var _results_refresh_accum: float = 0.0
var _leaderboard_refresh_accum: float = 0.0
## The event's challenges (from GameModeEventDefinition). Resolved from ctx in Enter.
var _race_challenges: Array[RaceChallenge] = []
## peer_id -> stats (see _peer_stats), frozen when the human crosses the finish line so
## tricks after it don't count. Server only.
var _finished_stats: Dictionary[int, Dictionary] = {}


func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.current_game_mode = GameModeType.Kind.STUNT_RACE
	DebugUtils.DebugMsg("Stunt Race Mode")

	var ctx := state_context as GamemodeStateContext
	_start_circle = ctx.event_start_circle
	if ctx.gamemode_event != null:
		_race_challenges = ctx.gamemode_event.race_challenges
	_start_circle.enable_game_objects()
	_runners = _start_circle.get_runners()
	_inject_runner_deps()

	gamemode_manager.player_crashed.connect(_on_player_crashed)
	gamemode_manager.player_disconnected.connect(_on_player_disconnected)
	gamemode_manager.player_latejoined.connect(_on_player_latejoined)
	results_hud.skip_pressed.connect(_on_results_skip_pressed)
	results_hud.restart_pressed.connect(_on_results_restart_pressed)
	trick_manager.combo_banked.connect(_on_combo_banked)
	trick_manager.combo_voided.connect(_on_combo_voided)

	if multiplayer.is_server():
		_race_task = _find_race_task(_start_circle)
		if _race_task is StuntRaceTask:
			(_race_task as StuntRaceTask).on_race_start()
		_reset_scoring()
		_setup_npcs()
		_start_next_runner()


func Update(delta: float):
	if !multiplayer.is_server():
		return
	_push_checkpoint_markers()
	_update_leaderboard(delta)
	if _update_results_countdown(delta):
		return
	if _active_runner != null:
		_active_runner.update(delta)


func Exit(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.player_crashed.disconnect(_on_player_crashed)
	gamemode_manager.player_disconnected.disconnect(_on_player_disconnected)
	gamemode_manager.player_latejoined.disconnect(_on_player_latejoined)
	results_hud.skip_pressed.disconnect(_on_results_skip_pressed)
	results_hud.restart_pressed.disconnect(_on_results_restart_pressed)
	trick_manager.combo_banked.disconnect(_on_combo_banked)
	trick_manager.combo_voided.disconnect(_on_combo_voided)

	if _active_runner != null:
		_disconnect_runner(_active_runner)
		_active_runner.stop()
		_active_runner = null

	if multiplayer.is_server():
		# CountdownTask disables input on_enter; if we exit mid-task on_exit never runs.
		_reset_all_player_input()
		if _race_task is StuntRaceTask:
			(_race_task as StuntRaceTask).on_race_end()
		_teardown_npcs()
		_clear_checkpoint_markers()
		riding_hud_state.clear_leaderboard()
		_race_task = null

	if results_hud.ui.visible:
		input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME
	tutorial_hud.hide_ui()
	results_hud.hide_ui()
	_start_circle.disable_game_objects()
	_start_circle = null
	_runners = []
	_active_runner_index = -1
	_human_rows = []
	_race_challenges = []
	_finished_stats.clear()


#region Runner chaining


func _start_next_runner():
	_active_runner_index += 1
	if _active_runner_index >= _runners.size():
		_return_to_free_roam()
		return
	_active_runner = _runners[_active_runner_index]
	_active_runner.all_completed.connect(_on_runner_all_completed)
	_active_runner.player_completed.connect(_on_runner_player_completed)
	_active_runner.respawn_requested.connect(_on_runner_respawn_requested)
	_active_runner.start(lobby_manager.lobby_players.keys())


func _on_runner_all_completed():
	var completed_runner := _active_runner
	_disconnect_runner(completed_runner)
	_active_runner = null
	var is_last := _active_runner_index + 1 >= _runners.size()
	if is_last:
		_show_results()
	completed_runner.stop()
	if !is_last:
		_start_next_runner()


func _disconnect_runner(runner: TaskRunner):
	if runner.all_completed.is_connected(_on_runner_all_completed):
		runner.all_completed.disconnect(_on_runner_all_completed)
	if runner.player_completed.is_connected(_on_runner_player_completed):
		runner.player_completed.disconnect(_on_runner_player_completed)
	if runner.respawn_requested.is_connected(_on_runner_respawn_requested):
		runner.respawn_requested.disconnect(_on_runner_respawn_requested)


#endregion

#region Setup


func _inject_runner_deps():
	for runner in _runners:
		runner.spawn_manager = spawn_manager
		runner.task_hud = tutorial_hud
		runner.audio_manager = audio_manager
		runner.wire_task_refs()


func _reset_all_player_input():
	for peer_id in lobby_manager.lobby_players:
		# Player may not be spawned yet — skip is intentional
		var player := spawn_manager._get_player_by_peer_id(peer_id)
		if player == null:
			continue
		player.input_controller.input_disabled = false
		player.rb_unlock_movement = true


## Server only. Push each human's next checkpoint to their own minimap (green
## marker). get_target_checkpoint returns null pre-race/finished — that clears it.
func _push_checkpoint_markers():
	if _race_task == null:
		return
	for peer_id in lobby_manager.lobby_players:
		# Player may not be spawned yet (late-join) — skip is intentional.
		var player := spawn_manager._get_player_by_peer_id(peer_id)
		if player == null:
			continue
		var pos := Vector3.ZERO
		var has_target := false
		if _race_task.has_racer(peer_id):
			var ckpt := _race_task.get_target_checkpoint(peer_id)
			if ckpt != null:
				pos = ckpt.global_position
				has_target = true
		riding_hud_state.push_checkpoint_marker(peer_id, pos, has_target)


func _clear_checkpoint_markers():
	for peer_id in lobby_manager.lobby_players:
		# Player may not be spawned yet (late-join) — skip is intentional.
		var player := spawn_manager._get_player_by_peer_id(peer_id)
		if player == null:
			continue
		riding_hud_state.push_checkpoint_marker(peer_id, Vector3.ZERO, false)


#endregion

#region Scoring + leaderboard (server only)


## Fresh race: zero every human's trick score and challenge bests, unfreeze finishers.
func _reset_scoring():
	_finished_stats.clear()
	var peer_ids := lobby_manager.lobby_players.keys()
	for peer_id in peer_ids:
		trick_manager.reset_peer(peer_id)
	for challenge in _race_challenges:
		challenge.reset(peer_ids)


## One human's race stats — the shape the leaderboard, results, and (later) progression read.
## Finishers return their frozen snapshot.
func _peer_stats(peer_id: int) -> Dictionary:
	if _finished_stats.has(peer_id):
		return _finished_stats[peer_id]
	var bests: Array[float] = []
	for challenge in _race_challenges:
		bests.append(challenge.get_best(peer_id))
	return {
		"peer_id": peer_id,
		"username": lobby_manager.lobby_players[peer_id].username,
		"score": trick_manager.get_score(peer_id),
		"time_ms": -1.0,
		"place": 0,
		"bests": bests,
	}


## Freeze a finisher's stats and award placement points by finish order among humans.
func _finish_peer(peer_id: int):
	var stats := _peer_stats(peer_id)
	stats["time_ms"] = _race_task.get_completion_time_ms(peer_id)
	var place := _finished_stats.size()
	if place < placement_points.size():
		stats["score"] += placement_points[place]
	stats["place"] = place + 1
	_finished_stats[peer_id] = stats


## Every spawned human's stats, best score first.
func _sorted_stats() -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for peer_id in lobby_manager.lobby_players:
		# Player may not be spawned yet (late-join) — skip is intentional.
		if spawn_manager._get_player_by_peer_id(peer_id) == null:
			continue
		all.append(_peer_stats(peer_id))
	all.sort_custom(func(a, b): return a["score"] > b["score"])
	return all


## Tick every racing human's challenges, then broadcast the leaderboard at
## LEADERBOARD_REFRESH_SECS. Only runs while a leg is live — the race is over during results.
func _update_leaderboard(delta: float):
	if _active_runner == null:
		return
	for peer_id in lobby_manager.lobby_players:
		# Unspawned (late-join) and finished riders don't tick — skip is intentional.
		var player := spawn_manager._get_player_by_peer_id(peer_id)
		if player == null or _finished_stats.has(peer_id):
			continue
		for challenge in _race_challenges:
			challenge.tick(peer_id, player, delta)
	_leaderboard_refresh_accum -= delta
	if _leaderboard_refresh_accum > 0.0:
		return
	_leaderboard_refresh_accum = LEADERBOARD_REFRESH_SECS

	var headers := PackedStringArray(["", "🏁", "💰"])
	var tricks := PackedInt32Array()
	for challenge in _race_challenges:
		headers.append(challenge.icon)
		tricks.append_array(challenge.hint_tricks())
	var places := _human_race_places()
	var rows: Array = []
	for stats in _sorted_stats():
		var place: int = places.get(stats["peer_id"], 0)
		var cells := PackedStringArray([
			stats["username"],
			"P%d" % place if place > 0 else "—",
			"%d" % int(stats["score"]),
		])
		for i in _race_challenges.size():
			cells.append(_race_challenges[i].format_value(stats["bests"][i]))
		rows.append({"peer_id": stats["peer_id"], "cells": cells})
	riding_hud_state.push_leaderboard(headers, rows, tricks)


## 1-based race position per racing human — NPCs ignored, matching placement points.
func _human_race_places() -> Dictionary[int, int]:
	var keys: Dictionary[int, float] = {}
	for peer_id in lobby_manager.lobby_players:
		var player := spawn_manager._get_player_by_peer_id(peer_id)
		# Unspawned (late-join) or not in the race body yet — no place, skip is intentional.
		if player == null or !_race_task.has_racer(peer_id):
			continue
		keys[peer_id] = _race_task.get_progress_key(peer_id, player.global_position)
	var places: Dictionary[int, int] = {}
	for peer_id in keys:
		places[peer_id] = 1
		for other in keys:
			if keys[other] > keys[peer_id]:
				places[peer_id] += 1
	return places


func _on_combo_banked(peer_id: int, points: float, _duration: float, _multiplier: int):
	# Tricks past the finish line don't count — the finisher's stats are frozen.
	if !multiplayer.is_server() or _finished_stats.has(peer_id):
		return
	for challenge in _race_challenges:
		challenge.on_combo_banked(peer_id, points)


func _on_combo_voided(peer_id: int, _lost_duration: float, _lost_points: float):
	if !multiplayer.is_server() or _finished_stats.has(peer_id):
		return
	for challenge in _race_challenges:
		challenge.on_combo_voided(peer_id)


#endregion

#region NPC racers (server only)


## Spawns the event's NPCs at grid slots (from the back — humans keep the
## front rows) and registers them as racers in the RaceTask.
func _setup_npcs():
	if !_start_circle.enable_npcs:
		return
	var grid_markers := _find_grid_spawn_task(_start_circle).get_grid_markers()
	# Fill every grid slot the humans don't occupy.
	var npc_count := grid_markers.size() - lobby_manager.lobby_players.size()
	if npc_count <= 0:
		return
	npc_race_manager.race_task = _race_task
	for i in npc_count:
		var marker: Marker3D = grid_markers[maxi(0, grid_markers.size() - 1 - i)]
		var npc_id := npc_race_manager.spawn_npc(marker.global_position, marker.global_basis)
		_race_task.register_npc(npc_id)


func _teardown_npcs():
	var race_task := npc_race_manager.race_task
	if race_task != null:
		for npc_id in npc_race_manager.get_npc_ids():
			race_task.unregister_npc(npc_id)
		npc_race_manager.race_task = null
	npc_race_manager.despawn_all_npcs()


func _find_race_task(node: Node) -> RaceTask:
	if node is RaceTask:
		return node
	for child in node.get_children():
		var found := _find_race_task(child)
		if found != null:
			return found
	return null


func _find_grid_spawn_task(node: Node) -> GridSpawnTask:
	if node is GridSpawnTask:
		return node
	for child in node.get_children():
		var found := _find_grid_spawn_task(child)
		if found != null:
			return found
	return null


#endregion

#region Results


func _update_results_countdown(delta: float) -> bool:
	if _results_countdown <= 0.0:
		return false
	_results_countdown -= delta
	_results_refresh_accum -= delta
	if _results_refresh_accum <= 0.0:
		_results_refresh_accum = RESULTS_REFRESH_SECS
		results_hud.rpc_update_rows.rpc(_build_results_data().to_dict())
	if _results_countdown <= 0.0:
		_results_countdown = -1.0
		_return_to_free_roam()
	return true


func _show_results():
	_human_rows = []
	for stats in _finished_stats.values():
		_human_rows.append(_human_result_row(stats))
	_results_countdown = _results_countdown_total
	_results_refresh_accum = RESULTS_REFRESH_SECS
	tutorial_hud.rpc_hide.rpc()
	results_hud.rpc_show_results.rpc(_build_results_data().to_dict(), _results_countdown_total)


## Cached human rows (best score first) + live NPC rows below them by time. Bots keep racing
## through the results countdown — a bot that finishes mid-countdown gets its real time on the
## next refresh instead of a DNF. NPCs don't score, so their stat cells stay empty.
func _build_results_data() -> ResultsData:
	var rows: Array[Dictionary] = _human_rows.duplicate()
	if _race_task != null:
		for npc_id in npc_race_manager.get_npc_ids():
			var npc_name: String = npc_race_manager.get_npc(npc_id).username
			var time_ms := _race_task.get_completion_time_ms(npc_id)
			if time_ms >= 0.0:
				rows.append({
					"_peer_id": npc_id,
					"Username": npc_name,
					"Time": "%.1fs" % (time_ms / 1000.0),
					"_sort_key": NPC_SORT_OFFSET + time_ms,
				})
			else:
				rows.append({
					"_peer_id": npc_id, "Username": npc_name, "Time": tr("RACE_RACING"), "_sort_key": INF
				})
	rows.sort_custom(func(a, b): return a["_sort_key"] < b["_sort_key"])
	# Same icons as the live leaderboard.
	var columns: Array[String] = ["Username", "Time", "Place", "Score"]
	var headers: Array[String] = ["", "⏱", "🏁", "💰"]
	for challenge in _race_challenges:
		columns.append(challenge.title())
		headers.append(challenge.icon)
	return ResultsData.create(tr("RACE_COMPLETE"), columns, rows, headers)


func _human_result_row(stats: Dictionary) -> Dictionary:
	var row := {
		"_peer_id": stats["peer_id"],
		"Username": stats["username"],
		"Time": "%.1fs" % (stats["time_ms"] / 1000.0),
		"Place": "P%d" % stats["place"],
		"Score": "%d" % int(stats["score"]),
		"_sort_key": -stats["score"],
	}
	for i in _race_challenges.size():
		var challenge := _race_challenges[i]
		row[challenge.title()] = challenge.format_value(stats["bests"][i])
	return row


func _on_results_skip_pressed():
	if !multiplayer.is_server():
		return
	_results_countdown = -1.0
	_return_to_free_roam()


func _on_results_restart_pressed():
	if !multiplayer.is_server():
		return
	_results_countdown = -1.0
	results_hud.rpc_hide.rpc()
	# Active runner is already null here (results show only after all_completed),
	# but guard for the timing edge where restart races the countdown.
	if _active_runner != null:
		_disconnect_runner(_active_runner)
		_active_runner.stop()
		_active_runner = null
	_active_runner_index = -1
	_human_rows = []
	_reset_scoring()
	_runners = _start_circle.get_runners()
	_inject_runner_deps()
	# Fresh NPCs back at the grid with reset race rows.
	_teardown_npcs()
	_setup_npcs()
	_start_next_runner()


#endregion

#region Player event handlers


## Only the last runner's completion is crossing the race's finish line.
func _on_runner_player_completed(peer_id: int):
	if _active_runner_index == _runners.size() - 1:
		_finish_peer(peer_id)


func _on_player_crashed(peer_id: int):
	if !multiplayer.is_server():
		return
	if _active_runner != null:
		_active_runner.notify_crashed(peer_id)


func _on_runner_respawn_requested(peer_id: int):
	get_tree().create_timer(_respawn_delay).timeout.connect(
		func(): _respawn_crashed_racer(peer_id), CONNECT_ONE_SHOT
	)


## Delayed crash respawn — skip if the racer already recovered (R tap) before the timer fired,
## so we don't respawn twice.
func _respawn_crashed_racer(peer_id: int):
	if spawn_manager._get_player_by_peer_id(peer_id).is_crashed:
		spawn_manager.respawn_player.rpc(peer_id)


func _on_player_latejoined(peer_id: int):
	gamemode_manager.latespawn_player(peer_id)
	npc_race_manager.sync_npcs_to_peer(peer_id)


func _on_player_disconnected(peer_id: int):
	if gamemode_manager.match_state == GamemodeManager.MatchState.IN_GAME:
		spawn_manager.rpc_despawn_player.rpc(peer_id)
	if _active_runner != null:
		_active_runner.notify_disconnected(peer_id)


#endregion


func _return_to_free_roam():
	gamemode_manager.change_gamemode(
		GameModeType.Kind.FREE_ROAM, multiplayer.get_unique_id(), ^"",
		not teleport_to_start_on_finish
	)


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if tutorial_hud == null:
		issues.append("tutorial_hud must not be empty")
	if results_hud == null:
		issues.append("results_hud must not be empty")
	if input_state_manager == null:
		issues.append("input_state_manager must not be empty")
	if lobby_manager == null:
		issues.append("lobby_manager must not be empty")
	if menu_manager == null:
		issues.append("menu_manager must not be empty")
	if audio_manager == null:
		issues.append("audio_manager must not be empty")
	if npc_race_manager == null:
		issues.append("npc_race_manager must not be empty")
	if riding_hud_state == null:
		issues.append("riding_hud_state must not be empty")
	if trick_manager == null:
		issues.append("trick_manager must not be empty")

	return issues
