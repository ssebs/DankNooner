class_name TutorialPlayerState extends RefCounted

var current_index: int = 0
var started: bool = false
var completed: bool = false
var start_time: float = 0.0
var completion_time_ms: float = 0.0

## Per-lesson scratchpad. Mutated by the current Objective. Cleared on
## advance and on crash.
var lesson_state: Dictionary = {}

## Trigger gating for ON_ENTER (one-shot) / WHILE_INSIDE lessons.
## Set by the gamemode's signal handlers; cleared on lesson advance.
var prop_event_fired: bool = false
var inside_zone: bool = false


static func create() -> TutorialPlayerState:
	return TutorialPlayerState.new()
