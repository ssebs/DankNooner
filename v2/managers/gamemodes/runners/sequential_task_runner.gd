@tool
## Runs child GameModeTasks one at a time per peer.
##
## Lives as a child of an EventStartCircle (or nested under another runner).
## Owns the per-peer task walk, eval_when dispatch, and trigger wiring. The
## host gamemode delegates to this runner and listens to `all_completed`.
##
## A SequentialTaskRunner IS a GameModeTask (composite pattern) — it can be
## nested inside another runner as one "step."
class_name SequentialTaskRunner extends TaskRunner

var _wired_callables: Array = []

## When the per-peer walk lands on a child that is itself a TaskRunner, peers
## park at that index. Once all non-completed peers are parked there, we start
## the nested runner and wait for its `all_completed` before advancing.
var _nested_runner: TaskRunner
var _nested_runner_index: int = -1

#region Composite API


func start(peer_ids: Array) -> void:
	if Engine.is_editor_hint():
		return
	super(peer_ids)
	if multiplayer.is_server():
		_wire_objective_signals()
	_start_step_for_all()


func update(delta: float) -> void:
	if !_running or !multiplayer.is_server():
		return
	super(delta)
	_try_start_nested_runner()
	if _nested_runner != null:
		_nested_runner.update(delta)


func stop() -> void:
	if Engine.is_editor_hint():
		return
	if _nested_runner != null:
		_disconnect_nested_runner()
		_nested_runner.stop()
		_nested_runner = null
		_nested_runner_index = -1
	if multiplayer.is_server():
		_unwire_objective_signals()
	super()


func notify_crashed(peer_id: int) -> void:
	if !multiplayer.is_server():
		return
	# If a nested runner has this peer, it owns the crash response.
	if _nested_runner != null and _nested_runner.player_states.has(peer_id):
		_nested_runner.notify_crashed(peer_id)
		return
	# Crash signal may fire for players not in this runner — skip is intentional
	if !player_states.has(peer_id):
		return
	var state := player_states[peer_id]
	state.lesson_state = {}
	# Teleport on crash; clear in/out gating since Godot may not fire body_exited.
	state.prop_event_fired = false
	state.inside_zone = false
	respawn_requested.emit(peer_id, respawns_in_place(peer_id))


#override
func respawns_in_place(peer_id: int) -> bool:
	if _nested_runner != null and _nested_runner.player_states.has(peer_id):
		return _nested_runner.respawns_in_place(peer_id)
	# Late joiners free-roam outside the runner — skip is intentional
	if !player_states.has(peer_id):
		return false
	var task := get_current_task(peer_id)
	return task != null and task.respawn_in_place


func notify_disconnected(peer_id: int) -> void:
	if _nested_runner != null:
		_nested_runner.notify_disconnected(peer_id)
	super(peer_id)


#endregion

#region Task callbacks


## Called by tasks (e.g. CloseHelpTask ack RPC) to write into the per-peer scratchpad.
func mark_state(peer_id: int, key: String, value: Variant) -> void:
	# Player may have disconnected before the ack arrived — skip is intentional
	if !player_states.has(peer_id):
		return
	player_states[peer_id].lesson_state[key] = value


#endregion

#region Per-peer walk


## The peer's step (a nested runner while parked at its gate); null once they've finished.
func get_current_task(peer_id: int) -> GameModeTask:
	var state := player_states[peer_id]
	return null if state.completed else tasks[state.current_index]


func _update_player(
	peer_id: int, state: PlayerTaskState, player: PlayerEntity, delta: float
) -> void:
	var task := tasks[state.current_index]
	# Peer is parked at a nested-runner gate — _try_start_nested_runner handles it.
	if task is TaskRunner:
		return

	var progress := task.get_progress(state.lesson_state)
	if progress != "":
		riding_hud.push_event_progress(peer_id, progress)

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
	if state.current_index >= tasks.size():
		_complete_player(peer_id, state)
	else:
		_start_step_for_peer(peer_id, state)


func _start_step_for_all() -> void:
	for peer_id in player_states:
		_start_step_for_peer(peer_id, player_states[peer_id])


func _start_step_for_peer(peer_id: int, state: PlayerTaskState) -> void:
	var task := tasks[state.current_index]
	# Nested runner — peer just parks here; the runner pushes its own HUD when it starts.
	if task is TaskRunner:
		return
	# Player may not be spawned yet during late-join sync — pass null is intentional
	var player := spawn_manager.get_player_by_peer_id(peer_id)
	task.on_enter(player, state.lesson_state)
	riding_hud.push_event_step(
		peer_id,
		state.current_index,
		tasks.size(),
		task.get_objective_text(),
		task.get_hint_text(),
		show_step_count
	)


#endregion

#region Nested runner gate


## Starts a nested TaskRunner child once every non-completed peer has advanced
## to its index. Sequential semantics: the gate blocks until everyone has
## finished the preceding leaf tasks.
func _try_start_nested_runner() -> void:
	if _nested_runner != null:
		return
	var gate_index := -1
	var peers_at_gate: Array[int] = []
	for peer_id in player_states:
		var s := player_states[peer_id]
		if s.completed:
			continue
		if tasks[s.current_index] is TaskRunner:
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
	_nested_runner = tasks[gate_index] as TaskRunner
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
	for peer_id in player_states:
		var s := player_states[peer_id]
		if s.completed:
			continue
		if s.current_index == idx:
			_advance_player(peer_id, s)


func _disconnect_nested_runner() -> void:
	if _nested_runner.all_completed.is_connected(_on_nested_runner_completed):
		_nested_runner.all_completed.disconnect(_on_nested_runner_completed)
	if _nested_runner.respawn_requested.is_connected(_forward_nested_respawn):
		_nested_runner.respawn_requested.disconnect(_forward_nested_respawn)


func _forward_nested_respawn(peer_id: int, in_place: bool) -> void:
	respawn_requested.emit(peer_id, in_place)


#endregion

#region Trigger wiring (server only)


func _wire_objective_signals() -> void:
	var seen := {}
	for task in tasks:
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


func _on_trigger_entered(racer: Node3D, obj: GameModeObject) -> void:
	var peer_id := int(racer.name)
	# Body may be a racer not in this runner (spectator, late-joiner, NPC) — skip is intentional
	if !player_states.has(peer_id):
		return
	var state := player_states[peer_id]
	if state.completed or !state.started:
		return
	var task := tasks[state.current_index]
	if task.trigger != obj:
		return
	match task.eval_when:
		GameModeTask.EvalWhen.ALWAYS:
			# The task reads it itself (LongJumpTask's start gate); cleared with the scratchpad.
			state.lesson_state["trigger_entered"] = true
		GameModeTask.EvalWhen.ON_ENTER:
			state.prop_event_fired = true
		GameModeTask.EvalWhen.WHILE_INSIDE:
			state.inside_zone = true


func _on_trigger_exited(racer: Node3D, obj: GameModeObject) -> void:
	var peer_id := int(racer.name)
	if !player_states.has(peer_id):
		return
	var state := player_states[peer_id]
	if state.completed or !state.started:
		return
	var task := tasks[state.current_index]
	if task.trigger != obj:
		return
	if task.eval_when == GameModeTask.EvalWhen.WHILE_INSIDE:
		state.inside_zone = false

#endregion

## Deps are injected by the host gamemode at runtime — no editor-time check.
