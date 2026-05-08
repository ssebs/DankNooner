@tool
class_name TutorialGameMode extends GameMode

@export var tutorial_hud: TutorialHUD
@export var results_hud: ResultsHUD
@export var input_state_manager: InputStateManager
@export var lobby_manager: LobbyManager
@export var menu_manager: MenuManager
@export var help_menu_state: HelpMenuState

var _player_states: Dictionary[int, TutorialPlayerState] = {}
var _start_circle: EventStartCircle
var _objectives: Array[GameModeObjective] = []
var _wired_callables: Array = []  # tracked so we can disconnect on Exit
## Per-peer respawn override set by TeleportTutorialStep. Falls back to start_marker.
var _respawn_overrides: Dictionary[int, Marker3D] = {}
var _respawn_delay: float = 3.0
var _countdown: float = -1.0
var _results_countdown: float = -1.0
var _results_countdown_total: float = 10.0


func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.current_game_mode = GamemodeManager.TGameMode.TUTORIAL
	DebugUtils.DebugMsg("Tutorial Mode")

	var ctx := state_context as GamemodeStateContext
	var event := ctx.gamemode_event
	_start_circle = ctx.event_start_circle
	_objectives = _start_circle.get_objectives()
	for obj in _objectives:
		obj._gamemode = self
	_build_player_states()
	if multiplayer.is_server():
		_wire_objective_signals()

	gamemode_manager.player_crashed.connect(_on_player_crashed)
	gamemode_manager.player_disconnected.connect(_on_player_disconnected)
	gamemode_manager.player_latejoined.connect(_on_player_latejoined)
	results_hud.skip_pressed.connect(_on_results_skip_pressed)

	if multiplayer.is_server():
		_teleport_players_to_start()
		if event.countdown_seconds > 0.0:
			_set_all_players_input_disabled(true)
			_countdown = event.countdown_seconds
			_rpc_show_countdown.rpc(ceili(_countdown))
		else:
			_on_countdown_finished()


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
	results_hud.skip_pressed.disconnect(_on_results_skip_pressed)

	if multiplayer.is_server():
		_set_all_players_input_disabled(false)
		_unwire_objective_signals()
	# Hide locally rather than via RPC — when leaving via pause→main menu the peer is
	# torn down before Exit runs, which silently drops the .rpc() local-call. Each peer
	# runs Exit() on their own state machine, so a local hide is sufficient.
	# results_hud sets IN_GAME_PAUSED when it shows; restore IN_GAME on the way out so
	# the cursor doesn't stay visible after skip→free-roam.
	if results_hud.visible:
		input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME
	tutorial_hud.hide()
	results_hud.hide()
	for obj in _objectives:
		obj._gamemode = null
	_player_states.clear()
	_respawn_overrides.clear()
	_start_circle = null
	_objectives = []


## Called by objectives (e.g. CloseHelpTutorialStep ack RPC) to write into the
## per-peer scratchpad without coupling the gamemode to the step's logic.
func mark_objective_state(peer_id: int, key: String, value: Variant):
	# Player may have disconnected before the ack arrived — skip is intentional
	if !_player_states.has(peer_id):
		return
	_player_states[peer_id].lesson_state[key] = value


## Called by TeleportTutorialStep to set this peer's crash-respawn target for
## the rest of the tutorial. Subsequent crashes use this instead of start_marker.
func set_respawn_marker(peer_id: int, marker: Marker3D):
	_respawn_overrides[peer_id] = marker


#region Setup helpers


func _build_player_states():
	_player_states.clear()
	for peer_id in lobby_manager.lobby_players:
		_player_states[peer_id] = TutorialPlayerState.create()


func _teleport_players_to_start():
	var marker := _start_circle.start_marker
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

	# Pause progress while crashed/respawning. trick_controller freezes current_trick
	# during a crash, so without this guard a wheelie/stoppie timer would keep ticking
	# through the respawn delay.
	if player.is_crashed:
		return

	var objective := _objectives[state.current_index]

	var progress := objective.get_progress(state.lesson_state)
	if progress != "":
		tutorial_hud.rpc_update_progress.rpc_id(peer_id, progress)

	if !_should_eval_predicate(objective, state):
		return

	if objective.check(player, delta, state.lesson_state):
		objective.on_exit(player, state.lesson_state)
		_advance_player_step(peer_id, state)


## Decides whether to evaluate this peer's objective this tick, based on the
## objective's eval_when policy.
func _should_eval_predicate(objective: GameModeObjective, state: TutorialPlayerState) -> bool:
	match objective.eval_when:
		GameModeObjective.EvalWhen.ALWAYS:
			return true
		GameModeObjective.EvalWhen.ON_ENTER:
			# One-shot: gate fired this tick. Evaluated once; flag clears.
			if state.prop_event_fired:
				state.prop_event_fired = false
				return true
			return false
		GameModeObjective.EvalWhen.WHILE_INSIDE:
			return state.inside_zone
	return true


func _advance_player_step(peer_id: int, state: TutorialPlayerState):
	state.current_index += 1
	state.lesson_state = {}
	state.prop_event_fired = false
	state.inside_zone = false
	if state.current_index >= _objectives.size():
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
	var objective := _objectives[state.current_index]

	# Player may not be spawned yet during late-join sync — pass null is intentional
	var player := spawn_manager._get_player_by_peer_id(peer_id)
	objective.on_enter(player, state.lesson_state)

	tutorial_hud.rpc_show_step.rpc_id(
		peer_id,
		state.current_index,
		_objectives.size(),
		objective.get_objective_text(),
		objective.get_hint_text()
	)


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

	# Crash signal can fire for players not in the tutorial or who disconnected — skip is intentional
	if _player_states.has(peer_id):
		var state := _player_states[peer_id]
		state.lesson_state = {}
		# Player teleports back to start on crash; clear in/out tracking so the
		# zone's body_exited (which Godot may not fire on teleport) can't strand us.
		state.prop_event_fired = false
		state.inside_zone = false

	var marker: Marker3D = _respawn_overrides.get(peer_id, _start_circle.start_marker)
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
	_respawn_overrides.erase(peer_id)

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

#region Objective trigger wiring (server only)


## Connects entered/exited signals from every unique GameModeObject referenced
## by any objective's `trigger`. Routes to the matching peer state via the body
## name convention (`int(body.name) == peer_id`).
func _wire_objective_signals():
	var seen := {}
	for objective in _objectives:
		var obj := objective.trigger
		if obj == null or seen.has(obj):
			continue
		seen[obj] = true
		var cb_in := _on_trigger_entered.bind(obj)
		var cb_out := _on_trigger_exited.bind(obj)
		obj.entered.connect(cb_in)
		obj.exited.connect(cb_out)
		_wired_callables.append({"obj": obj, "sig": "entered", "cb": cb_in})
		_wired_callables.append({"obj": obj, "sig": "exited", "cb": cb_out})


func _unwire_objective_signals():
	for w in _wired_callables:
		var obj: GameModeObject = w["obj"]
		if w["sig"] == "entered":
			if obj.entered.is_connected(w["cb"]):
				obj.entered.disconnect(w["cb"])
		else:
			if obj.exited.is_connected(w["cb"]):
				obj.exited.disconnect(w["cb"])
	_wired_callables.clear()


func _on_trigger_entered(player: PlayerEntity, obj: GameModeObject):
	var peer_id := int(player.name)
	# Body may be a player not in this tutorial (spectator, late-joiner) — skip is intentional
	if !_player_states.has(peer_id):
		return
	var state := _player_states[peer_id]
	if state.completed or !state.started:
		return
	var objective := _objectives[state.current_index]
	if objective.trigger != obj:
		return
	match objective.eval_when:
		GameModeObjective.EvalWhen.ON_ENTER:
			state.prop_event_fired = true
		GameModeObjective.EvalWhen.WHILE_INSIDE:
			state.inside_zone = true


func _on_trigger_exited(player: PlayerEntity, obj: GameModeObject):
	var peer_id := int(player.name)
	# Body may be a player not in this tutorial (spectator, late-joiner) — skip is intentional
	if !_player_states.has(peer_id):
		return
	var state := _player_states[peer_id]
	if state.completed or !state.started:
		return
	var objective := _objectives[state.current_index]
	if objective.trigger != obj:
		return
	if objective.eval_when == GameModeObjective.EvalWhen.WHILE_INSIDE:
		state.inside_zone = false


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
