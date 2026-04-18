@tool
class_name TutorialGameMode extends GameMode

@export var tutorial_hud: TutorialHUD
@export var results_hud: ResultsHUD
@export var input_state_manager: InputStateManager
@export var lobby_manager: LobbyManager
@export var menu_manager: MenuManager
@export var help_menu_state: HelpMenuState

var _player_states: Dictionary[int, TutorialPlayerState] = {}
var _sequence: Array[TutorialSteps.Step] = []
var _respawn_delay: float = 3.0
var _countdown: float = -1.0
var _countdown_total: float = 3.0
var _results_countdown: float = -1.0
var _results_countdown_total: float = 10.0


func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.current_game_mode = GamemodeManager.TGameMode.TUTORIAL
	DebugUtils.DebugMsg("Tutorial Mode")

	_sequence = _get_sequence(state_context)
	_build_player_states()

	gamemode_manager.player_crashed.connect(_on_player_crashed)
	gamemode_manager.player_disconnected.connect(_on_player_disconnected)
	gamemode_manager.player_latejoined.connect(_on_player_latejoined)

	if multiplayer.is_server():
		_set_all_players_input_disabled(true)
		_teleport_players_to_start()
		_countdown = _countdown_total
		_rpc_show_countdown.rpc(ceili(_countdown))


func Update(delta: float):
	if !multiplayer.is_server():
		return

	if _update_countdown(delta):
		return

	if _update_results_countdown(delta):
		return

	for peer_id in _player_states:
		var state := _player_states[peer_id]
		if state.completed or !state.started:
			continue
		_update_player_tutorial(peer_id, state, delta)

	_check_all_complete()


func Exit(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.player_crashed.disconnect(_on_player_crashed)
	gamemode_manager.player_disconnected.disconnect(_on_player_disconnected)
	gamemode_manager.player_latejoined.disconnect(_on_player_latejoined)

	if multiplayer.is_server():
		_set_all_players_input_disabled(false)
	tutorial_hud.rpc_hide.rpc()
	results_hud.rpc_hide.rpc()
	_player_states.clear()


#region Setup helpers


func _get_sequence(state_context: StateContext) -> Array[TutorialSteps.Step]:
	if state_context is GamemodeStateContext:
		var ctx := state_context as GamemodeStateContext
		if ctx.gamemode_event and ctx.gamemode_event.tutorial_sequence.size() > 0:
			return ctx.gamemode_event.tutorial_sequence
	# Clients don't receive the event through RPC — only the server needs the sequence
	if multiplayer.is_server():
		DebugUtils.DebugErrMsg("failed to load GamemodeStateContext in tutorial_gamemode/_get_sequence")
	return []


func _build_player_states():
	_player_states.clear()
	for peer_id in lobby_manager.lobby_players:
		_player_states[peer_id] = TutorialPlayerState.create()


func _get_start_marker() -> Marker3D:
	return gamemode_manager.level_manager.current_level.get_node("%Tutorial01StartMarker")


func _teleport_players_to_start():
	var marker := _get_start_marker()
	for peer_id in lobby_manager.lobby_players:
		spawn_manager.respawn_player_at.rpc(peer_id, marker.global_position, marker.global_basis)


#endregion

#region Countdown phases


func _update_countdown(delta: float) -> bool:
	if _countdown <= 0.0:
		return false

	var prev_sec := ceili(_countdown)
	_countdown -= delta
	var curr_sec := ceili(_countdown)
	if curr_sec != prev_sec and curr_sec > 0:
		_rpc_show_countdown.rpc(curr_sec)
	if _countdown <= 0.0:
		_countdown = -1.0
		_on_countdown_finished()
	return true


func _on_countdown_finished():
	_set_all_players_input_disabled(false)
	var now := Time.get_ticks_msec() as float
	for peer_id in _player_states:
		var state := _player_states[peer_id]
		state.started = true
		state.start_time = now
	_start_step_for_all()


func _update_results_countdown(delta: float) -> bool:
	if _results_countdown <= 0.0:
		return false
	_results_countdown -= delta
	if _results_countdown <= 0.0:
		_results_countdown = -1.0
		_return_to_free_roam()
	return true


#endregion

#region Per-player tutorial logic


func _update_player_tutorial(peer_id: int, state: TutorialPlayerState, delta: float):
	# Player may not be spawned yet during late-join sync — skip is intentional
	var player := spawn_manager._get_player_by_peer_id(peer_id)
	if player == null:
		return

	var step_def := state.tutorial_steps.defs[_sequence[state.current_index]]

	if step_def.get_progress.is_valid():
		tutorial_hud.rpc_update_progress.rpc_id(peer_id, step_def.get_progress.call())

	if step_def.check.call(player, delta):
		if step_def.on_exit.is_valid():
			step_def.on_exit.call()
		_advance_player_step(peer_id, state)


func _advance_player_step(peer_id: int, state: TutorialPlayerState):
	state.current_index += 1
	if state.current_index >= _sequence.size():
		_complete_player(peer_id, state)
	else:
		_start_step_for_peer(peer_id, state)


func _complete_player(peer_id: int, state: TutorialPlayerState):
	state.completed = true
	state.completion_time_ms = Time.get_ticks_msec() - state.start_time
	tutorial_hud.rpc_show_waiting.rpc_id(peer_id)


func _start_step_for_all():
	for peer_id in _player_states:
		_start_step_for_peer(peer_id, _player_states[peer_id])


func _start_step_for_peer(peer_id: int, state: TutorialPlayerState):
	var step_enum := _sequence[state.current_index]
	var step_def := state.tutorial_steps.defs[step_enum]
	if step_def.on_enter.is_valid():
		step_def.on_enter.call()
	tutorial_hud.rpc_show_step.rpc_id(
		peer_id, state.current_index, _sequence.size(), step_def.objective_text, step_def.hint_text
	)
	if step_enum == TutorialSteps.Step.SHOW_HELP:
		_rpc_show_help_menu.rpc_id(peer_id)


#endregion

#region All-complete check & results


func _check_all_complete():
	if _results_countdown > 0.0:
		return
	for peer_id in _player_states:
		if !_player_states[peer_id].completed:
			return
	_show_results()


func _show_results():
	var rows: Array[Dictionary] = []
	for peer_id in _player_states:
		var state := _player_states[peer_id]
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


#endregion

#region Help menu (per-player)

@rpc("call_local", "reliable")
func _rpc_show_help_menu():
	var player := spawn_manager._get_player_by_peer_id(multiplayer.get_unique_id())
	player.input_controller.input_disabled = true

	input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME_PAUSED
	menu_manager.enable_input_and_processing()
	help_menu_state.ui.show()
	help_menu_state._show_controls_for_current_device()

	help_menu_state.close_help_btn.pressed.connect(_on_tutorial_help_closed, CONNECT_ONE_SHOT)
	input_state_manager.unpause_requested.connect(_on_tutorial_help_closed, CONNECT_ONE_SHOT)


func _on_tutorial_help_closed():
	if help_menu_state.close_help_btn.pressed.is_connected(_on_tutorial_help_closed):
		help_menu_state.close_help_btn.pressed.disconnect(_on_tutorial_help_closed)
	if input_state_manager.unpause_requested.is_connected(_on_tutorial_help_closed):
		input_state_manager.unpause_requested.disconnect(_on_tutorial_help_closed)

	help_menu_state.ui.hide()
	menu_manager.disable_input_and_processing()
	input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME

	var player := spawn_manager._get_player_by_peer_id(multiplayer.get_unique_id())
	player.input_controller.input_disabled = false

	_rpc_help_menu_closed.rpc_id(1, multiplayer.get_unique_id())


@rpc("call_local", "any_peer", "reliable")
func _rpc_help_menu_closed(peer_id: int):
	# Player may have disconnected before this RPC arrived — skip is intentional
	if !_player_states.has(peer_id):
		return
	_player_states[peer_id].tutorial_steps._help_closed = true


#endregion

#region Player event handlers


func _on_player_crashed(peer_id: int):
	if !multiplayer.is_server():
		return

	# Crash signal can fire for players not in the tutorial or who disconnected — skip is intentional
	if _player_states.has(peer_id):
		var state := _player_states[peer_id]
		state.tutorial_steps._wheelie_time = 0.0
		state.tutorial_steps._stoppie_time = 0.0

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

	_player_states.erase(peer_id)

	# If the only remaining players are all complete, show results
	if multiplayer.is_server() and _player_states.size() > 0:
		_check_all_complete()


#endregion

#region Navigation


func _return_to_free_roam():
	gamemode_manager._rpc_transition_gamemode.rpc(
		GamemodeManager.TGameMode.FREE_FROAM, multiplayer.get_unique_id()
	)


#endregion

#region Input helpers


func _set_all_players_input_disabled(disabled: bool):
	for peer_id in lobby_manager.lobby_players:
		# Player may not be spawned yet — skip is intentional
		var player := spawn_manager._get_player_by_peer_id(peer_id)
		if player == null:
			continue
		player.input_controller.input_disabled = disabled
		if disabled:
			player.input_controller.nfx_throttle = 0.0
			player.input_controller.nfx_front_brake = 0.0
			player.input_controller.nfx_rear_brake = 0.0
			player.input_controller.nfx_steer = 0.0
			player.input_controller.nfx_lean = 0.0


#endregion

@rpc("call_local", "reliable")
func _rpc_show_countdown(seconds: int):
	tutorial_hud.rpc_show_countdown(seconds)


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
	if help_menu_state == null:
		issues.append("help_menu_state must not be empty")

	return issues
