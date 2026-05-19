class_name PlayerTaskState extends RefCounted

var current_index: int = 0
var started: bool = false
var completed: bool = false
var start_time: float = 0.0
var completion_time_ms: float = 0.0

## Per-task scratchpad. Mutated by the current GameModeTask via its hooks.
## Cleared on advance to next task and on crash. See GameModeTask header for the contract.
var lesson_state: Dictionary = {}

## Trigger gating for ON_ENTER (one-shot) / WHILE_INSIDE tasks.
## Set by the runner's signal handlers; cleared on advance.
var prop_event_fired: bool = false
var inside_zone: bool = false


static func create() -> PlayerTaskState:
	return PlayerTaskState.new()
