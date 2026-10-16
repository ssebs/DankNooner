extends RefCounted
## Director side: turns each rider's current task into a DriveBot order (see drive_bot.gd).
## A task class with no solver fails the run loudly, so a new task type forces adding one here.

const IDLE := {"mode": "idle"}
const HOLD := {"mode": "hold"}
## An air-trick rider this far past its closest approach to the ramp missed it, and is respawned
const AIR_TRICK_OVERSHOOT := 25.0
const AIR_TRICK_NEAR := 15.0
const AIR_TRICKS: Array[int] = [
	TrickController.Trick.BACKFLIP,
	TrickController.Trick.FRONTFLIP,
	TrickController.Trick.SPREAD_EAGLE,
	TrickController.Trick.SUPERMAN,
]

## The TestRunner. Untyped: it preloads this script, and a cyclic preload won't resolve.
var _runner: Node
## Script -> Callable(task, peer_id) -> order
var _solvers: Dictionary = {}
var _reported: Dictionary = {}
## peer_id -> closest distance to the current air-trick ramp
var _closest: Dictionary[int, float] = {}


func _init(runner: Node) -> void:
	_runner = runner
	_solvers = {
		GridSpawnTask: _idle,
		GridRespawnTask: _idle,
		TeleportTask: _idle,
		SFXTask: _idle,
		CountdownTask: _hold,
		RaceTask: _race,
		CheckpointTask: _checkpoint,
		SpeedAboveTask: _straight,
		ChangeGearTask: _change_gear,
		WheelieDurationTask: _wheelie,
		StoppieDurationTask: _stoppie,
		PerformTrickTask: _perform_trick,
		LongJumpTask: _long_jump,
		TrickBattleTask: _trick_battle,
		MaintainTrickTask: _maintain_trick,
	}


## The runner of `event` that's running, or null between runners.
static func active_runner(event: GameModeEvent) -> TaskRunner:
	for runner in event.get_runners():
		if !runner.player_states.is_empty():
			return runner
	return null


## The leaf task `peer_id` is on, or null (no event, finished, parked at a gate).
static func current_task(event: GameModeEvent, peer_id: int) -> GameModeTask:
	var runner := active_runner(event)
	while runner != null and runner.player_states.has(peer_id):
		if runner is ConcurrentTaskRunner:
			return null
		var task := (runner as SequentialTaskRunner).get_current_task(peer_id)
		if task is not TaskRunner:
			return task
		runner = task as TaskRunner
	return null


func order_for(event: GameModeEvent, peer_id: int) -> Dictionary:
	var runner := active_runner(event)
	while runner != null and runner.player_states.has(peer_id):
		if runner is ConcurrentTaskRunner:
			return _concurrent_order(runner, peer_id)
		var task := (runner as SequentialTaskRunner).get_current_task(peer_id)
		if task == null:
			return IDLE  # finished, waiting on the others
		if task is not TaskRunner:
			return _solve(task, peer_id)
		runner = task as TaskRunner
	# Parked at a gate, or between runners
	return IDLE


## The first child that has somewhere to go, plus any constraint's trick.
func _concurrent_order(runner: ConcurrentTaskRunner, peer_id: int) -> Dictionary:
	var order: Dictionary = HOLD
	for task in runner.tasks:
		if task.is_constraint:
			continue
		var task_order := _solve(task, peer_id)
		if task_order["mode"] == "go":
			order = task_order.duplicate()
			break
	for task in runner.tasks:
		if task.is_constraint:
			order = order.duplicate()
			order.merge(_solve(task, peer_id), true)
	return order


func _solve(task: GameModeTask, peer_id: int) -> Dictionary:
	var script: Script = task.get_script()
	if !_solvers.has(script):
		_report("no solver for task %s (%s)" % [script.get_global_name(), task.get_path()])
		return IDLE
	return _solvers[script].call(task, peer_id)


func _idle(_task: GameModeTask, _peer_id: int) -> Dictionary:
	return IDLE


func _hold(_task: GameModeTask, _peer_id: int) -> Dictionary:
	return HOLD


func _race(task: RaceTask, peer_id: int) -> Dictionary:
	# Null before the race body starts and once this rider finished
	var checkpoint := task.get_target_checkpoint(peer_id)
	if checkpoint == null:
		return IDLE
	return _go(checkpoint.global_position)


func _checkpoint(task: CheckpointTask, _peer_id: int) -> Dictionary:
	return _go(task.trigger.global_position)


func _straight(_task: GameModeTask, _peer_id: int) -> Dictionary:
	return _go(null)


func _change_gear(_task: ChangeGearTask, _peer_id: int) -> Dictionary:
	var order := _go(null)
	order["gear"] = true
	return order


func _wheelie(_task: WheelieDurationTask, _peer_id: int) -> Dictionary:
	return _go(null, TrickController.Trick.WHEELIE_SITTING)


func _stoppie(_task: StoppieDurationTask, _peer_id: int) -> Dictionary:
	return _go(null, TrickController.Trick.STOPPIE)


func _perform_trick(task: PerformTrickTask, peer_id: int) -> Dictionary:
	var aim: Node3D = task.success_zone if task.success_zone != null else task.trigger
	if task.required_trick not in AIR_TRICKS:
		return _go(null if aim == null else aim.global_position, task.required_trick)
	if aim == null:
		_report("air trick task %s needs a success_zone or trigger at its ramp" % task.get_path())
		return IDLE
	_respawn_on_overshoot(peer_id, aim.global_position)
	return _go(aim.global_position, task.required_trick)


## Through the start gate, then straight on over the jump.
func _long_jump(task: LongJumpTask, peer_id: int) -> Dictionary:
	var state: Dictionary = task.runner.player_states[peer_id].lesson_state
	return _go(null if state.get("trigger_entered", false) else task.trigger.global_position)


func _trick_battle(_task: TrickBattleTask, _peer_id: int) -> Dictionary:
	return _go(null, TrickController.Trick.WHEELIE_SITTING)


## Merged into the objective's order by _concurrent_order.
func _maintain_trick(task: MaintainTrickTask, _peer_id: int) -> Dictionary:
	return {"trick": task.required_tricks[0]}


func _go(target: Variant, trick: int = TrickController.Trick.NONE) -> Dictionary:
	return {"mode": "go", "target": target, "trick": trick}


## A rider that drove past the ramp without the trick goes back to its respawn point for another run.
func _respawn_on_overshoot(peer_id: int, ramp: Vector3) -> void:
	var player: PlayerEntity = _runner.spawn_manager.get_player_by_peer_id(peer_id)
	var distance := player.global_position.distance_to(ramp)
	var closest: float = _closest.get(peer_id, INF)
	if distance < closest:
		_closest[peer_id] = distance
	elif closest < AIR_TRICK_NEAR and distance > closest + AIR_TRICK_OVERSHOOT:
		_closest.erase(peer_id)
		_runner.spawn_manager.respawn_player.rpc(peer_id)


func _report(message: String) -> void:
	if !_reported.has(message):
		_reported[message] = true
		_runner.violate(message)
