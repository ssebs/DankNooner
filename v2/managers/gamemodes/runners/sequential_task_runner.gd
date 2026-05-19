@tool
## Runs child GameModeTasks one at a time per peer.
##
## Lives as a child of an EventStartCircle (or nested under another runner).
## Owns the per-peer task walk, eval_when dispatch, and trigger wiring. The
## host gamemode delegates to this runner and listens to `all_completed`.
##
## A SequentialTaskRunner IS a GameModeTask (composite pattern) — it can be
## nested inside another runner as one "step."
class_name SequentialTaskRunner extends GameModeTask

## Per-peer respawn override set by TeleportTask. Forwarded to the gamemode
## via `respawn_requested` so the gamemode owns the actual respawn timer.
signal respawn_requested(peer_id: int, marker: Marker3D)

## Shared deps for child tasks. Tasks reach them via `_runner.spawn_manager` /
## `_runner.task_hud` instead of downcasting to a specific gamemode.
##
## Set by the host gamemode (or a parent runner, for nested cases) before
## `start()`. Not @exported because the runner lives in a level scene while the
## managers live in main_game.tscn — cross-scene NodePaths would be fragile.
var spawn_manager: SpawnManager
var task_hud: TutorialHUD
var audio_manager: AudioManager

var _player_states: Dictionary[int, PlayerTaskState] = {}
var _tasks: Array[GameModeTask] = []
var _respawn_overrides: Dictionary[int, Marker3D] = {}
var _wired_callables: Array = []
var _running: bool = false

## When the per-peer walk lands on a child that is itself a SequentialTaskRunner,
## peers park at that index. Once all non-completed peers are parked there, we
## start the nested runner and wait for its `all_completed` before advancing.
var _nested_runner: SequentialTaskRunner
var _nested_runner_index: int = -1


#region Composite API


func start(peer_ids: Array) -> void:
	if Engine.is_editor_hint():
		return
	_collect_tasks()
	_player_states.clear()
	var now := Time.get_ticks_msec() as float
	for peer_id in peer_ids:
		var state := PlayerTaskState.create()
		state.started = true
		state.start_time = now
		_player_states[peer_id] = state
	for task in _tasks:
		task._runner = self
		# Propagate shared deps into nested runners so they don't need wiring.
		if task is SequentialTaskRunner:
			task.spawn_manager = spawn_manager
			task.task_hud = task_hud
			task.audio_manager = audio_manager
	if multiplayer.is_server():
		_wire_objective_signals()
	_running = true
	_start_step_for_all()


func update(delta: float) -> void:
	if !_running or !multiplayer.is_server():
		return
	for peer_id in _player_states:
		var state := _player_states[peer_id]
		if state.completed or !state.started:
			continue
		_update_player(peer_id, state, delta)
	_try_start_nested_runner()
	if _nested_runner != null:
		_nested_runner.update(delta)


func stop() -> void:
	if Engine.is_editor_hint():
		return
	_running = false
	if _nested_runner != null:
		_disconnect_nested_runner()
		_nested_runner.stop()
		_nested_runner = null
		_nested_runner_index = -1
	if multiplayer.is_server():
		_unwire_objective_signals()
	for task in _tasks:
		task._runner = null
	_player_states.clear()
	_respawn_overrides.clear()
	_tasks = []


func notify_crashed(peer_id: int) -> void:
	if !multiplayer.is_server():
		return
	# If a nested runner has this peer, it owns the crash response.
	if _nested_runner != null and _nested_runner._player_states.has(peer_id):
		_nested_runner.notify_crashed(peer_id)
		return
	# Crash signal may fire for players not in this runner — skip is intentional
	if !_player_states.has(peer_id):
		return
	var state := _player_states[peer_id]
	state.lesson_state = {}
	# Teleport on crash; clear in/out gating since Godot may not fire body_exited.
	state.prop_event_fired = false
	state.inside_zone = false
	var marker: Marker3D = _respawn_overrides.get(peer_id, null)
	respawn_requested.emit(peer_id, marker)


func notify_disconnected(peer_id: int) -> void:
	if _nested_runner != null:
		_nested_runner.notify_disconnected(peer_id)
	_player_states.erase(peer_id)
	_respawn_overrides.erase(peer_id)


#endregion

#region Task callbacks


## Called by tasks (e.g. CloseHelpTask ack RPC) to write into the per-peer scratchpad.
func mark_state(peer_id: int, key: String, value: Variant) -> void:
	# Player may have disconnected before the ack arrived — skip is intentional
	if !_player_states.has(peer_id):
		return
	_player_states[peer_id].lesson_state[key] = value


## Called by TeleportTask to set this peer's crash-respawn target for the
## remainder of this runner. Subsequent crashes will use this marker.
func set_respawn_marker(peer_id: int, marker: Marker3D) -> void:
	_respawn_overrides[peer_id] = marker


#endregion

#region Per-peer walk


func _collect_tasks() -> void:
	_tasks = []
	for c in get_children():
		if c is GameModeTask:
			_tasks.append(c)


func _update_player(peer_id: int, state: PlayerTaskState, delta: float) -> void:
	var task := _tasks[state.current_index]
	# Peer is parked at a nested-runner gate — _try_start_nested_runner handles it.
	if task is SequentialTaskRunner:
		return

	# Player may not be spawned yet during late-join sync — skip is intentional
	var player := spawn_manager._get_player_by_peer_id(peer_id)
	if player == null:
		return

	# Pause progress while crashed/respawning. trick_controller freezes current_trick
	# during a crash, so without this guard a wheelie/stoppie timer would keep ticking
	# through the respawn delay.
	if player.is_crashed:
		return

	var progress := task.get_progress(state.lesson_state)
	if progress != "":
		task_hud.rpc_update_progress.rpc_id(peer_id, progress)

	if !_should_eval(task, state):
		return

	if task.check(player, delta, state.lesson_state):
		task.on_exit(player, state.lesson_state)
		_advance_player(peer_id, state)


func _should_eval(task: GameModeTask, state: PlayerTaskState) -> bool:
	match task.eval_when:
		GameModeTask.EvalWhen.ALWAYS:
			return true
		GameModeTask.EvalWhen.ON_ENTER:
			if state.prop_event_fired:
				state.prop_event_fired = false
				return true
			return false
		GameModeTask.EvalWhen.WHILE_INSIDE:
			return state.inside_zone
	return true


func _advance_player(peer_id: int, state: PlayerTaskState) -> void:
	state.current_index += 1
	state.lesson_state = {}
	state.prop_event_fired = false
	state.inside_zone = false
	if state.current_index >= _tasks.size():
		_complete_player(peer_id, state)
	else:
		_start_step_for_peer(peer_id, state)


func _complete_player(peer_id: int, state: PlayerTaskState) -> void:
	state.completed = true
	state.completion_time_ms = Time.get_ticks_msec() - state.start_time
	task_hud.rpc_show_waiting.rpc_id(peer_id)
	player_completed.emit(peer_id)
	if _all_peers_complete():
		all_completed.emit()


func _all_peers_complete() -> bool:
	for peer_id in _player_states:
		if !_player_states[peer_id].completed:
			return false
	return _player_states.size() > 0


func _start_step_for_all() -> void:
	for peer_id in _player_states:
		_start_step_for_peer(peer_id, _player_states[peer_id])


func _start_step_for_peer(peer_id: int, state: PlayerTaskState) -> void:
	var task := _tasks[state.current_index]
	# Nested runner — peer just parks here; the runner pushes its own HUD when it starts.
	if task is SequentialTaskRunner:
		return
	# Player may not be spawned yet during late-join sync — pass null is intentional
	var player := spawn_manager._get_player_by_peer_id(peer_id)
	task.on_enter(player, state.lesson_state)
	task_hud.rpc_show_step.rpc_id(
		peer_id,
		state.current_index,
		_tasks.size(),
		task.get_objective_text(),
		task.get_hint_text()
	)


#endregion

#region Nested runner gate


## Starts a nested SequentialTaskRunner child once every non-completed peer has
## advanced to its index. Sequential semantics: the gate blocks until everyone
## has finished the preceding leaf tasks.
func _try_start_nested_runner() -> void:
	if _nested_runner != null:
		return
	var gate_index := -1
	var peers_at_gate: Array[int] = []
	for peer_id in _player_states:
		var s := _player_states[peer_id]
		if s.completed:
			continue
		if _tasks[s.current_index] is SequentialTaskRunner:
			if gate_index == -1:
				gate_index = s.current_index
			elif s.current_index != gate_index:
				# Different peers are parked at different gates — wait.
				return
			peers_at_gate.append(peer_id)
		else:
			# Some peer hasn't reached the gate yet.
			return
	if gate_index == -1 or peers_at_gate.is_empty():
		return
	_nested_runner = _tasks[gate_index] as SequentialTaskRunner
	_nested_runner_index = gate_index
	_nested_runner.all_completed.connect(_on_nested_runner_completed)
	_nested_runner.respawn_requested.connect(_forward_nested_respawn)
	_nested_runner.start(peers_at_gate)


func _on_nested_runner_completed() -> void:
	var completed := _nested_runner
	var idx := _nested_runner_index
	_disconnect_nested_runner()
	_nested_runner = null
	_nested_runner_index = -1
	completed.stop()
	# Advance every peer parked at this gate past it.
	for peer_id in _player_states:
		var s := _player_states[peer_id]
		if s.completed:
			continue
		if s.current_index == idx:
			_advance_player(peer_id, s)


func _disconnect_nested_runner() -> void:
	if _nested_runner.all_completed.is_connected(_on_nested_runner_completed):
		_nested_runner.all_completed.disconnect(_on_nested_runner_completed)
	if _nested_runner.respawn_requested.is_connected(_forward_nested_respawn):
		_nested_runner.respawn_requested.disconnect(_forward_nested_respawn)


func _forward_nested_respawn(peer_id: int, marker: Marker3D) -> void:
	respawn_requested.emit(peer_id, marker)


#endregion

#region Trigger wiring (server only)


func _wire_objective_signals() -> void:
	var seen := {}
	for task in _tasks:
		var obj := task.trigger
		if obj == null or seen.has(obj):
			continue
		seen[obj] = true
		var cb_in := _on_trigger_entered.bind(obj)
		var cb_out := _on_trigger_exited.bind(obj)
		obj.entered.connect(cb_in)
		obj.exited.connect(cb_out)
		_wired_callables.append({"obj": obj, "sig": "entered", "cb": cb_in})
		_wired_callables.append({"obj": obj, "sig": "exited", "cb": cb_out})


func _unwire_objective_signals() -> void:
	for w in _wired_callables:
		var obj: GameModeObject = w["obj"]
		if w["sig"] == "entered":
			if obj.entered.is_connected(w["cb"]):
				obj.entered.disconnect(w["cb"])
		else:
			if obj.exited.is_connected(w["cb"]):
				obj.exited.disconnect(w["cb"])
	_wired_callables.clear()


func _on_trigger_entered(player: PlayerEntity, obj: GameModeObject) -> void:
	var peer_id := int(player.name)
	# Body may be a player not in this runner (spectator, late-joiner) — skip is intentional
	if !_player_states.has(peer_id):
		return
	var state := _player_states[peer_id]
	if state.completed or !state.started:
		return
	var task := _tasks[state.current_index]
	if task.trigger != obj:
		return
	match task.eval_when:
		GameModeTask.EvalWhen.ON_ENTER:
			state.prop_event_fired = true
		GameModeTask.EvalWhen.WHILE_INSIDE:
			state.inside_zone = true


func _on_trigger_exited(player: PlayerEntity, obj: GameModeObject) -> void:
	var peer_id := int(player.name)
	if !_player_states.has(peer_id):
		return
	var state := _player_states[peer_id]
	if state.completed or !state.started:
		return
	var task := _tasks[state.current_index]
	if task.trigger != obj:
		return
	if task.eval_when == GameModeTask.EvalWhen.WHILE_INSIDE:
		state.inside_zone = false


#endregion


## Deps are injected by the host gamemode at runtime — no editor-time check.
