class_name TutorialPlayerState extends RefCounted

var tutorial_steps: TutorialSteps
var current_index: int = 0
var started: bool = false
var completed: bool = false
var start_time: float = 0.0
var completion_time_ms: float = 0.0

## --- Lesson-driven trigger state (only used when running a TutorialCourse) ---
## Set by the gamemode's signal handlers; cleared on lesson advance.
var prop_event_fired: bool = false
var inside_zone: bool = false


static func create() -> TutorialPlayerState:
	var state := TutorialPlayerState.new()
	state.tutorial_steps = TutorialSteps.new()
	return state
