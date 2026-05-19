@tool
class_name TutorialGameMode extends GameModeType

@export var tutorial_hud: TutorialHUD
@export var results_hud: ResultsHUD
@export var input_state_manager: InputStateManager
@export var lobby_manager: LobbyManager
@export var menu_manager: MenuManager
@export var audio_manager: AudioManager
@export var help_menu_state: HelpMenuState

var _start_circle: EventStartCircle
var _runners: Array[SequentialTaskRunner] = []
var _active_runner: SequentialTaskRunner
var _active_runner_index: int = -1
var _respawn_delay: float = 3.0
var _results_countdown: float = -1.0
var _results_countdown_total: float = 10.0


func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.current_game_mode = GameModeType.Kind.TUTORIAL
	DebugUtils.DebugMsg("Tutorial Mode")

	var ctx := state_context as GamemodeStateContext
	_start_circle = ctx.event_start_circle
	_runners = _start_circle.get_runners()
	_inject_runner_deps()

	gamemode_manager.player_crashed.connect(_on_player_crashed)
	gamemode_manager.player_disconnected.connect(_on_player_disconnected)
	gamemode_manager.player_latejoined.connect(_on_player_latejoined)
	results_hud.skip_pressed.connect(_on_results_skip_pressed)

	if multiplayer.is_server():
		_teleport_players_to_start()
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

	if _active_runner != null:
		_disconnect_runner(_active_runner)
		_active_runner.stop()
		_active_runner = null

	if multiplayer.is_server():
		# Tasks (Countdown, CloseHelp) disable input during their on_enter. If we
		# exit mid-task (player quit, skip) on_exit never runs — reset everyone.
		_reset_all_player_input()

	# Hide locally rather than via RPC — when leaving via pause→main menu the peer is
	# torn down before Exit runs, which silently drops the .rpc() local-call. Each peer
	# runs Exit() on their own state machine, so a local hide is sufficient.
	# results_hud sets IN_GAME_PAUSED when it shows; restore IN_GAME on the way out so
	# the cursor doesn't stay visible after skip→free-roam.
	if results_hud.visible:
		input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME
	tutorial_hud.hide()
	results_hud.hide()
	_start_circle = null
	_runners = []
	_active_runner_index = -1


#region Runner chaining


func _start_next_runner():
	_active_runner_index += 1
	if _active_runner_index >= _runners.size():
		# Should only happen if the circle has zero runners — normal flow shows
		# results on the last runner's all_completed.
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


func _disconnect_runner(runner: SequentialTaskRunner):
	if runner.all_completed.is_connected(_on_runner_all_completed):
		runner.all_completed.disconnect(_on_runner_all_completed)
	if runner.respawn_requested.is_connected(_on_runner_respawn_requested):
		runner.respawn_requested.disconnect(_on_runner_respawn_requested)


#endregion

#region Setup


## Inject runtime deps into level-authored runners and tutorial-specific tasks.
## Cross-scene NodePath @exports would be fragile; setting plain vars is cleaner.
func _inject_runner_deps():
	for runner in _runners:
		runner.spawn_manager = spawn_manager
		runner.task_hud = tutorial_hud
		runner.audio_manager = audio_manager
		_inject_task_deps(runner)


func _inject_task_deps(runner: SequentialTaskRunner):
	for child in runner.get_children():
		if child is CloseHelpTask:
			child.input_state_manager = input_state_manager
			child.menu_manager = menu_manager
			child.help_menu_state = help_menu_state
		elif child is SequentialTaskRunner:
			_inject_task_deps(child)


func _reset_all_player_input():
	for peer_id in lobby_manager.lobby_players:
		# Player may not be spawned yet — skip is intentional
		var player := spawn_manager._get_player_by_peer_id(peer_id)
		if player == null:
			continue
		player.input_controller.input_disabled = false


func _teleport_players_to_start():
	var marker := _start_circle.start_marker
	for peer_id in lobby_manager.lobby_players:
		spawn_manager.respawn_player_at.rpc(peer_id, marker.global_position, marker.global_basis)


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


func _show_results(runner: SequentialTaskRunner):
	var rows: Array[Dictionary] = []
	for peer_id in runner._player_states:
		var state := runner._player_states[peer_id]
		var username: String = lobby_manager.lobby_players[peer_id].username
		var time_sec := state.completion_time_ms / 1000.0
		(
			rows
			. append(
				{
					"Username": username,
					"Time": "%.1fs" % time_sec,
					"_sort_key": state.completion_time_ms,
				}
			)
		)
	rows.sort_custom(func(a, b): return a["_sort_key"] < b["_sort_key"])

	var data := ResultsData.create(tr("TUT_COMPLETE"), ["Username", "Time"], rows)
	_results_countdown = _results_countdown_total
	tutorial_hud.rpc_hide.rpc()
	results_hud.rpc_show_results.rpc(data.to_dict(), _results_countdown_total)


func _on_results_skip_pressed():
	if !multiplayer.is_server():
		return
	_results_countdown = -1.0
	_return_to_free_roam()


#endregion

#region Player event handlers


func _on_player_crashed(peer_id: int):
	if !multiplayer.is_server():
		return
	if _active_runner != null:
		_active_runner.notify_crashed(peer_id)
	# respawn_requested signal from the runner schedules the actual respawn —
	# fallback to start_marker here for the case the runner doesn't fire it
	# (e.g. crash arrived after the runner completed all peers).


func _on_runner_respawn_requested(peer_id: int, marker: Marker3D):
	# Runner may pass null when no override was set — fall back to start.
	if marker == null:
		marker = _start_circle.start_marker
	get_tree().create_timer(_respawn_delay).timeout.connect(
		func():
			spawn_manager.respawn_player_at.rpc(
				peer_id, marker.global_position, marker.global_basis
			),
		CONNECT_ONE_SHOT
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
		GameModeType.Kind.FREE_FROAM, multiplayer.get_unique_id()
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
	if help_menu_state == null:
		issues.append("help_menu_state must not be empty")

	return issues
