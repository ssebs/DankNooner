@tool
## Base class for one step in a gamemode course (tutorial / race / future modes).
##
## Lives as a child of a TaskRunner (e.g. SequentialTaskRunner). The runner walks
## children in tree order. Each subclass is a self-contained Node — it can hold
## its own RPCs and @export the managers it needs.
##
## Composite: a runner is itself a GameModeTask. That lets you nest runners
## inside other runners (e.g. SequentialTaskRunner [intro tasks ... ConcurrentTaskRunner ... outro tasks]).
##
## Per-peer scratchpad: `state: Dictionary`
##   - One dict per peer, owned by the runner (`_player_states[peer_id].lesson_state`).
##   - Passed into every leaf hook. Tasks read/write whatever keys they need
##     (e.g. StoppieDurationTask uses `state["t"]` to accumulate elapsed hold time).
##   - Cleared on advance (next task starts with empty {}) and on crash.
##   - Untyped on purpose — each task chooses its own keys.
##
## - eval_when : ALWAYS / ON_ENTER / WHILE_INSIDE   (leaf tasks only)
## - trigger   : required for ON_ENTER / WHILE_INSIDE — a level-authored GameModeObject
class_name GameModeTask extends Node

enum EvalWhen { ALWAYS, ON_ENTER, WHILE_INSIDE }

@export var eval_when: EvalWhen = EvalWhen.ALWAYS
@export var trigger: GameModeObject

## Constraint tasks tick every frame alongside the objective tasks but never gate
## completion — their check() return value is ignored when deciding if a peer is
## done. Use for fail-conditions that run for the whole objective (hold a trick,
## maintain speed, stay in bounds). Honored by ConcurrentTaskRunner.
@export var is_constraint: bool = false

## Set by the parent runner when the task becomes active.
## Tasks reach shared deps (spawn_manager, task_hud, audio_manager) via this ref
## instead of downcasting to a specific gamemode or runner subclass.
var _runner: TaskRunner

#region Leaf-task hooks (override in leaf subclasses)


func on_enter(_player: PlayerEntity, _state: Dictionary) -> void:
	pass


func check(_player: PlayerEntity, _delta: float, _state: Dictionary) -> bool:
	return false


func on_exit(_player: PlayerEntity, _state: Dictionary) -> void:
	pass


func get_progress(_state: Dictionary) -> String:
	return ""


func get_objective_text() -> String:
	return ""


func get_hint_text() -> String:
	return ""


#endregion

#region Composite/runner API (override in TaskRunner subclasses)
## Leaf tasks ignore these — the parent runner walks them via the leaf hooks above.
## Runner subclasses override to manage their own children.

signal player_completed(peer_id: int)
signal all_completed


func start(_peer_ids: Array) -> void:
	pass


func update(_delta: float) -> void:
	pass


func stop() -> void:
	pass


func notify_crashed(_peer_id: int) -> void:
	pass


func notify_disconnected(_peer_id: int) -> void:
	pass


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	if eval_when != EvalWhen.ALWAYS and trigger == null:
		issues.append("trigger must be set for ON_ENTER / WHILE_INSIDE")
	return issues
