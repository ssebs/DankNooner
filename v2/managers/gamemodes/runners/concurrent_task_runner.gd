@tool
## Runs every child GameModeTask in parallel per peer.
##
## Use when several leaf tasks should be active at the same time — e.g. a
## countdown HUD and an SFX, or several "passive" race-body checks
## (lap counter, place tracker, out-of-bounds).
##
## Per peer, every child's on_enter fires immediately; each child's check()
## ticks every frame until it returns true; the peer completes when every
## child has reported done. Trigger gating is not supported here — children
## must use eval_when = ALWAYS. Nest a SequentialTaskRunner inside if you need
## trigger-gated steps.
##
## The runner pushes a single objective/hint line to the HUD on start. Set
## `objective_text` / `hint_text` on the node; individual children's
## `get_objective_text()` is ignored.
class_name ConcurrentTaskRunner extends TaskRunner

## Optional HUD text pushed once when the runner starts.
@export var objective_text: String
@export var hint_text: String

## Per-peer scratchpad layout (stored on PlayerTaskState.lesson_state):
##   "_done"   : Array[bool]        — completion flag per child
##   "_states" : Array[Dictionary]  — one scratchpad per child
const _DONE := "_done"
const _STATES := "_states"

var _player_states: Dictionary[int, PlayerTaskState] = {}
var _tasks: Array[GameModeTask] = []
var _running: bool = false

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
		state.lesson_state = _fresh_lesson_state()
		_player_states[peer_id] = state
	for task in _tasks:
		task._runner = self
	_running = true
	for peer_id in _player_states:
		_on_enter_all(peer_id, _player_states[peer_id])
	_push_step_hud()


func update(delta: float) -> void:
	if !_running or !multiplayer.is_server():
		return
	for peer_id in _player_states:
		var state := _player_states[peer_id]
		if state.completed or !state.started:
			continue
		_update_player(peer_id, state, delta)


func stop() -> void:
	if Engine.is_editor_hint():
		return
	_running = false
	for task in _tasks:
		task._runner = null
	_player_states.clear()
	_tasks = []


func notify_crashed(peer_id: int) -> void:
	if !multiplayer.is_server():
		return
	# Crash signal may fire for players not in this runner — skip is intentional
	if !_player_states.has(peer_id):
		return
	var state := _player_states[peer_id]
	state.lesson_state = _fresh_lesson_state()
	# Tasks like CountdownTask disable input on_enter — re-running on_enter
	# resets their internal state so the player isn't stuck post-respawn.
	_on_enter_all(peer_id, state)
	respawn_requested.emit(peer_id, null)


func notify_disconnected(peer_id: int) -> void:
	_player_states.erase(peer_id)


#endregion

#region Per-peer parallel walk


func _collect_tasks() -> void:
	_tasks = []
	for c in get_children():
		if c is GameModeTask:
			_tasks.append(c)


func _fresh_lesson_state() -> Dictionary:
	var done: Array[bool] = []
	var states: Array[Dictionary] = []
	for i in _tasks.size():
		done.append(false)
		states.append({})
	return {_DONE: done, _STATES: states}


func _on_enter_all(peer_id: int, state: PlayerTaskState) -> void:
	# Player may not be spawned yet during late-join sync — pass null is intentional
	var player := spawn_manager._get_player_by_peer_id(peer_id)
	var states_arr: Array = state.lesson_state[_STATES]
	for i in _tasks.size():
		_tasks[i].on_enter(player, states_arr[i])


func _push_step_hud() -> void:
	for peer_id in _player_states:
		task_hud.rpc_show_step.rpc_id(peer_id, 0, 1, objective_text, hint_text)


func _update_player(peer_id: int, state: PlayerTaskState, delta: float) -> void:
	# Player may not be spawned yet during late-join sync — skip is intentional
	var player := spawn_manager._get_player_by_peer_id(peer_id)
	if player == null:
		return
	if player.is_crashed:
		return

	var done: Array = state.lesson_state[_DONE]
	var states_arr: Array = state.lesson_state[_STATES]
	var all_done := true
	for i in _tasks.size():
		if done[i]:
			continue
		var task := _tasks[i]
		if task.check(player, delta, states_arr[i]):
			task.on_exit(player, states_arr[i])
			done[i] = true
		else:
			all_done = false
	if all_done:
		_complete_player(peer_id, state)


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

#endregion
