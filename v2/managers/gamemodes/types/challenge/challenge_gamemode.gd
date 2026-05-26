@tool
## Lightweight gamemode for in-world trick challenges. Player enters an
## EventStartCircle targeting CHALLENGE → confirms → this gamemode runs the
## circle's task runners (typically a single PerformTrickTask) → returns to
## FreeRoam on completion. No results screen, no countdown.
class_name ChallengeGameMode extends GameModeType

@export var tutorial_hud: TutorialHUD
@export var lobby_manager: LobbyManager
@export var audio_manager: AudioManager

var _start_circle: EventStartCircle
var _runners: Array[TaskRunner] = []
var _active_runner: TaskRunner
var _active_runner_index: int = -1
var _respawn_delay: float = 3.0
var _complete_toast_duration: float = 3.0
var _complete_toast_remaining: float = -1.0


func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.current_game_mode = GameModeType.Kind.CHALLENGE
	DebugUtils.DebugMsg("Challenge Mode")

	var ctx := state_context as GamemodeStateContext
	_start_circle = ctx.event_start_circle
	_runners = _start_circle.get_runners()
	_inject_runner_deps()

	gamemode_manager.player_crashed.connect(_on_player_crashed)
	gamemode_manager.player_disconnected.connect(_on_player_disconnected)
	gamemode_manager.player_latejoined.connect(_on_player_latejoined)

	if multiplayer.is_server():
		_start_next_runner()


func Update(delta: float):
	if !multiplayer.is_server():
		return
	if _complete_toast_remaining > 0.0:
		_complete_toast_remaining -= delta
		if _complete_toast_remaining <= 0.0:
			_complete_toast_remaining = -1.0
			_return_to_free_roam()
		return
	if _active_runner != null:
		_active_runner.update(delta)


func Exit(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.player_crashed.disconnect(_on_player_crashed)
	gamemode_manager.player_disconnected.disconnect(_on_player_disconnected)
	gamemode_manager.player_latejoined.disconnect(_on_player_latejoined)

	if _active_runner != null:
		_disconnect_runner(_active_runner)
		_active_runner.stop()
		_active_runner = null

	tutorial_hud.hide()
	_start_circle = null
	_runners = []
	_active_runner_index = -1
	_complete_toast_remaining = -1.0


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
	completed_runner.stop()
	if is_last:
		tutorial_hud.rpc_show_complete.rpc("CHALLENGE_COMPLETE")
		_complete_toast_remaining = _complete_toast_duration
	else:
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
	if lobby_manager == null:
		issues.append("lobby_manager must not be empty")
	if audio_manager == null:
		issues.append("audio_manager must not be empty")
	return issues
