@tool
class_name StreetRaceGameMode extends GameModeType

@export var tutorial_hud: TutorialHUD
@export var results_hud: ResultsHUD
@export var input_state_manager: InputStateManager
@export var lobby_manager: LobbyManager
@export var menu_manager: MenuManager
@export var audio_manager: AudioManager
@export var npc_race_manager: NPCRaceManager

var _start_circle: EventStartCircle
var _runners: Array[TaskRunner] = []
var _active_runner: TaskRunner
var _active_runner_index: int = -1
var _respawn_delay: float = 3.0
var _results_countdown: float = -1.0
var _results_countdown_total: float = 10.0


func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.current_game_mode = GameModeType.Kind.STREET_RACE
	DebugUtils.DebugMsg("Street Race Mode")

	var ctx := state_context as GamemodeStateContext
	_start_circle = ctx.event_start_circle
	_start_circle.enable_game_objects()
	_runners = _start_circle.get_runners()
	_inject_runner_deps()

	gamemode_manager.player_crashed.connect(_on_player_crashed)
	gamemode_manager.player_disconnected.connect(_on_player_disconnected)
	gamemode_manager.player_latejoined.connect(_on_player_latejoined)
	results_hud.skip_pressed.connect(_on_results_skip_pressed)
	results_hud.restart_pressed.connect(_on_results_restart_pressed)

	if multiplayer.is_server():
		_setup_npcs()
		_start_next_runner()


func Update(delta: float):
	if !multiplayer.is_server():
		return
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

	if _active_runner != null:
		_disconnect_runner(_active_runner)
		_active_runner.stop()
		_active_runner = null

	if multiplayer.is_server():
		# CountdownTask disables input on_enter; if we exit mid-task on_exit never runs.
		_reset_all_player_input()
		_teardown_npcs()

	if results_hud.visible:
		input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME
	tutorial_hud.hide()
	results_hud.hide()
	_start_circle.disable_game_objects()
	_start_circle = null
	_runners = []
	_active_runner_index = -1


#region Runner chaining


func _start_next_runner():
	_active_runner_index += 1
	if _active_runner_index >= _runners.size():
		_return_to_free_roam()
		return
	_active_runner = _runners[_active_runner_index]
	_active_runner.all_completed.connect(_on_runner_all_completed)
	_active_runner.respawn_requested.connect(_on_runner_respawn_requested)
	_active_runner.start(lobby_manager.lobby_players.keys())


func _on_runner_all_completed():
	var completed_runner := _active_runner
	_disconnect_runner(completed_runner)
	_active_runner = null
	var is_last := _active_runner_index + 1 >= _runners.size()
	if is_last:
		_show_results(completed_runner)
	completed_runner.stop()
	if !is_last:
		_start_next_runner()


func _disconnect_runner(runner: TaskRunner):
	if runner.all_completed.is_connected(_on_runner_all_completed):
		runner.all_completed.disconnect(_on_runner_all_completed)
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


#endregion

#region NPC racers (server only)


## Spawns the event's NPCs at grid slots (from the back — humans keep the
## front rows) and registers them as racers in the RaceTask.
func _setup_npcs():
	if _start_circle.npc_count <= 0:
		return
	var race_task := _find_race_task(_start_circle)
	var grid_markers := _find_grid_spawn_task(_start_circle).grid_markers
	npc_race_manager.race_task = race_task
	for i in _start_circle.npc_count:
		var marker: Marker3D = grid_markers[maxi(0, grid_markers.size() - 1 - i)]
		var npc_id := npc_race_manager.spawn_npc(marker.global_position, marker.global_basis)
		race_task.register_npc(npc_id)


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
	if _results_countdown <= 0.0:
		_results_countdown = -1.0
		_return_to_free_roam()
	return true


func _show_results(runner: TaskRunner):
	var race_task := npc_race_manager.race_task
	var rows: Array[Dictionary] = []
	for peer_id in runner._player_states:
		var state = runner._player_states[peer_id] as PlayerTaskState
		var username: String = lobby_manager.lobby_players[peer_id].username
		# Prefer the RaceTask clock (starts at the race body, like the lap HUD
		# and NPC rows) over the runner clock (starts at grid/countdown).
		var time_ms: float = state.completion_time_ms
		if race_task != null and race_task._peer_progress.has(peer_id):
			time_ms = race_task._peer_progress[peer_id].get("completion_time_ms", time_ms)
		rows.append(_result_row(username, time_ms))
	if race_task != null:
		for npc_id in npc_race_manager.get_npc_ids():
			var npc_row: Dictionary = race_task._peer_progress[npc_id]
			var npc_name: String = npc_race_manager.get_npc(npc_id).username
			if npc_row.has("completion_time_ms"):
				rows.append(_result_row(npc_name, npc_row["completion_time_ms"]))
			else:
				# Race ended (all humans done) before this NPC finished.
				rows.append({"Username": npc_name, "Time": tr("RACE_DNF"), "_sort_key": INF})
	rows.sort_custom(func(a, b): return a["_sort_key"] < b["_sort_key"])

	var data := ResultsData.create(tr("RACE_COMPLETE"), ["Username", "Time"], rows)
	_results_countdown = _results_countdown_total
	tutorial_hud.rpc_hide.rpc()
	results_hud.rpc_show_results.rpc(data.to_dict(), _results_countdown_total)


func _result_row(username: String, time_ms: float) -> Dictionary:
	return {
		"Username": username,
		"Time": "%.1fs" % (time_ms / 1000.0),
		"_sort_key": time_ms,
	}


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
	_runners = _start_circle.get_runners()
	_inject_runner_deps()
	# Fresh NPCs back at the grid with reset race rows.
	_teardown_npcs()
	_setup_npcs()
	_start_next_runner()


#endregion

#region Player event handlers


func _on_player_crashed(peer_id: int):
	if !multiplayer.is_server():
		return
	if _active_runner != null:
		_active_runner.notify_crashed(peer_id)


func _on_runner_respawn_requested(peer_id: int):
	get_tree().create_timer(_respawn_delay).timeout.connect(
		func(): spawn_manager.respawn_player.rpc(peer_id), CONNECT_ONE_SHOT
	)


func _on_player_latejoined(peer_id: int):
	gamemode_manager.latespawn_player(peer_id)


func _on_player_disconnected(peer_id: int):
	if gamemode_manager.match_state == GamemodeManager.MatchState.IN_GAME:
		spawn_manager.rpc_despawn_player.rpc(peer_id)
	if _active_runner != null:
		_active_runner.notify_disconnected(peer_id)


#endregion


func _return_to_free_roam():
	gamemode_manager._rpc_transition_gamemode.rpc(
		GameModeType.Kind.FREE_ROAM, multiplayer.get_unique_id()
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

	return issues
