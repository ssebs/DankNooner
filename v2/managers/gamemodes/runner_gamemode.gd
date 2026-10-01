@tool
## Base for gamemodes that run a GameModeEvent's task runners: runner chaining, dep injection,
## crash respawn, late-join, disconnect, input reset, the results countdown and the return to
## free roam. Subclasses call
## super() from Enter/Update/Exit and override the _on_* hooks.
class_name RunnerGameMode extends GameModeType

## Hosts the event pane every runner's step text goes to.
@export var riding_hud_state: RidingHUDState
@export var lobby_manager: LobbyManager
@export var audio_manager: AudioManager
@export var results_hud: ResultsHUDState
@export var input_state_manager: InputStateManager
@export var _respawn_delay: float = 2.5

var _event: GameModeEvent
var _runners: Array[TaskRunner] = []
var _active_runner: TaskRunner
var _active_runner_index: int = -1
var _results_countdown: float = -1.0
var _results_countdown_total: float = 10.0


func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	var ctx := state_context as GamemodeStateContext
	_event = ctx.event
	if shows_event_props():
		_event.get_circle().set_active_event(_event)
	_runners = _event.get_runners()
	_inject_runner_deps()
	riding_hud_state.set_event_title(tr(_event.definition.name))
	results_hud.skip_pressed.connect(_on_results_skip_pressed)

	gamemode_manager.player_crashed.connect(_on_player_crashed)
	gamemode_manager.player_disconnected.connect(_on_player_disconnected)
	gamemode_manager.player_latejoined.connect(_on_player_latejoined)


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
	_results_countdown = -1.0
	# results_hud sets IN_GAME_PAUSED when it shows; restore IN_GAME on the way out so
	# the cursor doesn't stay visible after skip→free-roam.
	if results_hud.ui.visible:
		input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME
	results_hud.hide_ui()

	_stop_active_runner()

	if multiplayer.is_server():
		# Tasks (Countdown, CloseHelp) disable input during their on_enter. If we
		# exit mid-task (player quit, skip) on_exit never runs — reset everyone.
		_reset_all_player_input()

	# Clear locally rather than via RPC — when leaving via pause→main menu the peer is
	# torn down before Exit runs, which silently drops the .rpc() local-call.
	riding_hud_state.clear_event_text()
	_event.get_circle().set_active_event(null)
	_event = null
	_runners = []
	_active_runner_index = -1


## Whether Enter shows the event's props. Modes whose tasks reveal their own props return false.
func shows_event_props() -> bool:
	return true


## Whether the event pane shows "step N / total". Single-objective modes return false.
func shows_step_count() -> bool:
	return true


#region Runner chaining


func _start_next_runner():
	_active_runner_index += 1
	if _active_runner_index >= _runners.size():
		# Only reached if the event has no runners — normal flow ends in _on_last_runner_completed.
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
	var is_last := _is_last_runner()
	# Before stop() — it clears the runner's per-peer state that results read.
	if is_last:
		_on_last_runner_completed(completed_runner)
	completed_runner.stop()
	if !is_last:
		_start_next_runner()


## Override: the event is over. `runner` still holds its per-peer state.
func _on_last_runner_completed(_runner: TaskRunner):
	pass


## Override: a peer finished the active runner.
func _on_runner_player_completed(_peer_id: int):
	pass


func _is_last_runner() -> bool:
	return _active_runner_index == _runners.size() - 1


func _stop_active_runner():
	if _active_runner == null:
		return
	_disconnect_runner(_active_runner)
	_active_runner.stop()
	_active_runner = null


func _disconnect_runner(runner: TaskRunner):
	if runner.all_completed.is_connected(_on_runner_all_completed):
		runner.all_completed.disconnect(_on_runner_all_completed)
	if runner.player_completed.is_connected(_on_runner_player_completed):
		runner.player_completed.disconnect(_on_runner_player_completed)
	if runner.respawn_requested.is_connected(_on_runner_respawn_requested):
		runner.respawn_requested.disconnect(_on_runner_respawn_requested)


#endregion

#region Results


## Show the results screen; the event returns to free roam when its countdown runs out.
func _show_results(data: ResultsData):
	_results_countdown = _results_countdown_total
	riding_hud_state.push_event_clear_all()
	results_hud.rpc_show_results.rpc(data.to_dict(), _results_countdown_total)


## One row per peer of `runner`, fastest completion first.
func _completion_results(runner: TaskRunner, title_key: String) -> ResultsData:
	var rows: Array[Dictionary] = []
	for peer_id in runner.player_states:
		var state = runner.player_states[peer_id] as PlayerTaskState
		var username: String = lobby_manager.lobby_players[peer_id].username
		var time_sec: float = state.completion_time_ms / 1000.0
		(
			rows
			.append(
				{
					"Username": username,
					"Time": "%.1fs" % time_sec,
					"_sort_key": state.completion_time_ms,
				}
			)
		)
	rows.sort_custom(func(a, b): return a["_sort_key"] < b["_sort_key"])
	return ResultsData.create(tr(title_key), ["Username", "Time"], rows, ["", "⏱"])


## True while the results screen counts down (the event is over).
func _update_results_countdown(delta: float) -> bool:
	if _results_countdown <= 0.0:
		return false
	_results_countdown -= delta
	if _results_countdown <= 0.0:
		_results_countdown = -1.0
		_return_to_free_roam()
	return true


func _on_results_skip_pressed():
	if !multiplayer.is_server():
		return
	_results_countdown = -1.0
	_return_to_free_roam()


#endregion

#region Setup


## Inject runtime deps into level-authored runners. Cross-scene NodePath @exports would be
## fragile; setting plain vars is cleaner. Runs on every peer (see TaskRunner.wire_task_refs).
func _inject_runner_deps():
	for runner in _runners:
		runner.spawn_manager = spawn_manager
		runner.riding_hud = riding_hud_state
		runner.show_step_count = shows_step_count()
		runner.audio_manager = audio_manager
		runner.route = _event.route
		runner.wire_task_refs()


func _reset_all_player_input():
	for peer_id in lobby_manager.lobby_players:
		# Player may not be spawned yet — skip is intentional
		var player := spawn_manager.get_player_by_peer_id(peer_id)
		if player == null:
			continue
		player.input_controller.input_disabled = false
		player.rb_unlock_movement = true


#endregion

#region Player event handlers


func _on_player_crashed(peer_id: int):
	if !multiplayer.is_server():
		return
	# The runner's respawn_requested schedules the actual respawn. A crash after the runner
	# completed fires none; the player keeps their last persistent respawn point.
	if _active_runner != null:
		_active_runner.notify_crashed(peer_id)


## respawn_player uses the player's persistent rb_respawn_transform, set by the most recent
## TeleportTask / checkpoint via SpawnManager.
func _on_runner_respawn_requested(peer_id: int):
	get_tree().create_timer(_respawn_delay).timeout.connect(
		func(): _respawn_crashed_player(peer_id), CONNECT_ONE_SHOT
	)


## Delayed crash respawn — skip if the player already recovered (R tap) before the timer fired,
## so we don't respawn twice.
func _respawn_crashed_player(peer_id: int):
	if spawn_manager.get_player_by_peer_id(peer_id).is_crashed:
		spawn_manager.respawn_player.rpc(peer_id)


func _on_player_latejoined(peer_id: int):
	gamemode_manager.latespawn_player(peer_id)


func _on_player_disconnected(peer_id: int):
	if gamemode_manager.match_state == GamemodeManager.MatchState.IN_GAME:
		spawn_manager.rpc_despawn_player.rpc(peer_id)
	if _active_runner != null:
		_active_runner.notify_disconnected(peer_id)


#endregion


func _return_to_free_roam():
	gamemode_manager.change_gamemode(GameModeType.Kind.FREE_ROAM, multiplayer.get_unique_id())


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	if riding_hud_state == null:
		issues.append("riding_hud_state must not be empty")
	if lobby_manager == null:
		issues.append("lobby_manager must not be empty")
	if audio_manager == null:
		issues.append("audio_manager must not be empty")
	if results_hud == null:
		issues.append("results_hud must not be empty")
	if input_state_manager == null:
		issues.append("input_state_manager must not be empty")
	return issues
