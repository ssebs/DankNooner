class_name TutorialPlayerState extends RefCounted

var tutorial_steps: TutorialSteps
var current_index: int = 0
var started: bool = false
var completed: bool = false
var start_time: float = 0.0
var completion_time_ms: float = 0.0


static func create() -> TutorialPlayerState:
	var state := TutorialPlayerState.new()
	state.tutorial_steps = TutorialSteps.new()
	return state
