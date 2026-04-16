@tool
class_name TutorialGameMode extends GameMode

@export var tutorial_hud: TutorialHUD
@export var input_state_manager: InputStateManager
@export var lobby_manager: LobbyManager

var _steps_lib: TutorialSteps
var _current_sequence: Array[TutorialSteps.Step] = []
var _current_index: int = 0
var _target_peer_id: int = -1
var _respawn_delay: float = 3.0
var _countdown: float = -1.0
var _countdown_total: float = 3.0
var _started: bool = false
var _active_trick: TrickController.Trick = TrickController.Trick.NONE


func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return

	gamemode_manager.current_game_mode = GamemodeManager.TGameMode.TUTORIAL
	DebugUtils.DebugMsg("Tutorial Mode")

	if state_context is GamemodeStateContext:
		_target_peer_id = state_context.peer_id
	else:
		_target_peer_id = multiplayer.get_unique_id()

	gamemode_manager.player_crashed.connect(_on_player_crashed)
	gamemode_manager.player_disconnected.connect(_on_player_disconnected)
	gamemode_manager.player_latejoined.connect(_on_player_latejoined)

	_steps_lib = TutorialSteps.new()
	_current_sequence = TutorialSteps.THE_BASICS
	_current_index = 0
	_started = false

	if multiplayer.is_server():
		_set_all_players_input_disabled(true)
		_teleport_players_to_start()
		_countdown = _countdown_total
		_rpc_show_countdown.rpc(ceili(_countdown))


func Update(delta: float):
	if !multiplayer.is_server():
		return

	# Countdown phase
	if _countdown > 0.0:
		var prev_sec := ceili(_countdown)
		_countdown -= delta
		var curr_sec := ceili(_countdown)
		if curr_sec != prev_sec and curr_sec > 0:
			_rpc_show_countdown.rpc(curr_sec)
		if _countdown <= 0.0:
			_countdown = -1.0
			_started = true
			_set_all_players_input_disabled(false)
			_connect_trick_signals()
			_start_step(_current_index)
		return

	if !_started:
		return

	if _current_index >= _current_sequence.size():
		return

	var step_enum := _current_sequence[_current_index]
	var step_def := _steps_lib.defs[step_enum]

	# Player may not be spawned yet during late-join sync — skip is intentional
	var player := spawn_manager._get_player_by_peer_id(_target_peer_id)
	if player == null:
		return

	if step_def.get_progress.is_valid():
		tutorial_hud.rpc_update_progress.rpc(step_def.get_progress.call())

	DebugUtils.DebugMsg("TUT Update | step=%d | trick=%s | delta=%.4f | wheelie_t=%.2f | stoppie_t=%.2f" % [
		_current_index,
		TrickController.trick_to_str(_active_trick),
		delta,
		_steps_lib._wheelie_time,
		_steps_lib._stoppie_time,
	])

	if step_def.check.call(player, delta, _active_trick):
		if step_def.on_exit.is_valid():
			step_def.on_exit.call()
		_current_index += 1
		if _current_index >= _current_sequence.size():
			tutorial_hud.rpc_show_complete.rpc()
			get_tree().create_timer(3.0).timeout.connect(
				func(): _return_to_free_roam(), CONNECT_ONE_SHOT
			)
		else:
			_start_step(_current_index)


func _get_start_marker() -> Marker3D:
	return gamemode_manager.level_manager.current_level.get_node("%Tutorial01StartMarker")


func _teleport_players_to_start():
	var marker := _get_start_marker()
	for peer_id in lobby_manager.lobby_players:
		spawn_manager.respawn_player_at.rpc(peer_id, marker.global_position, marker.global_basis)


func _connect_trick_signals():
	var player := spawn_manager._get_player_by_peer_id(_target_peer_id)
	player.trick_controller.trick_started.connect(_on_trick_started)
	player.trick_controller.trick_ended.connect(_on_trick_ended)


func _disconnect_trick_signals():
	var player := spawn_manager._get_player_by_peer_id(_target_peer_id)
	# Player may have been despawned on disconnect — skip is intentional
	if player == null:
		return
	if player.trick_controller.trick_started.is_connected(_on_trick_started):
		player.trick_controller.trick_started.disconnect(_on_trick_started)
	if player.trick_controller.trick_ended.is_connected(_on_trick_ended):
		player.trick_controller.trick_ended.disconnect(_on_trick_ended)


func _on_trick_started(trick_type: TrickController.Trick):
	_active_trick = trick_type


func _on_trick_ended(_trick_type: TrickController.Trick):
	_active_trick = TrickController.Trick.NONE


func _set_all_players_input_disabled(disabled: bool):
	for peer_id in lobby_manager.lobby_players:
		var player := spawn_manager._get_player_by_peer_id(peer_id)
		# Player may not be spawned yet — skip is intentional
		if player == null:
			continue
		player.input_controller.input_disabled = disabled
		if disabled:
			# Zero out current input so they stop moving
			player.input_controller.nfx_throttle = 0.0
			player.input_controller.nfx_front_brake = 0.0
			player.input_controller.nfx_rear_brake = 0.0
			player.input_controller.nfx_steer = 0.0
			player.input_controller.nfx_lean = 0.0


@rpc("call_local", "reliable")
func _rpc_show_countdown(seconds: int):
	tutorial_hud.rpc_show_countdown(seconds)


func _start_step(index: int):
	var step_enum := _current_sequence[index]
	var step_def := _steps_lib.defs[step_enum]
	if step_def.on_enter.is_valid():
		step_def.on_enter.call()
	tutorial_hud.rpc_show_step.rpc(
		index, _current_sequence.size(), step_def.objective_text, step_def.hint_text
	)


func _return_to_free_roam():
	var ctx := GamemodeStateContext.new()
	ctx.peer_id = _target_peer_id
	gamemode_manager._rpc_transition_gamemode.rpc(
		GamemodeManager.TGameMode.FREE_FROAM as int, _target_peer_id
	)


func Exit(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.player_crashed.disconnect(_on_player_crashed)
	gamemode_manager.player_disconnected.disconnect(_on_player_disconnected)
	gamemode_manager.player_latejoined.disconnect(_on_player_latejoined)

	if multiplayer.is_server():
		_disconnect_trick_signals()
		_set_all_players_input_disabled(false)
	tutorial_hud.rpc_hide.rpc()


func _on_player_crashed(peer_id: int):
	if !multiplayer.is_server():
		return
	var marker := _get_start_marker()
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

	# If the tutorial player disconnected, return to free roam
	if peer_id == _target_peer_id and multiplayer.is_server():
		_return_to_free_roam()


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if tutorial_hud == null:
		issues.append("tutorial_hud must not be empty")
	if input_state_manager == null:
		issues.append("input_state_manager must not be empty")
	if lobby_manager == null:
		issues.append("lobby_manager must not be empty")

	return issues
