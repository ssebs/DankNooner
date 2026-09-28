@tool
## Lightweight gamemode for in-world trick challenges. Player enters an
## EventStartCircle targeting CHALLENGE → confirms → this gamemode runs the
## circle's task runners (typically a single PerformTrickTask) → returns to
## FreeRoam on completion. No results screen, no countdown.
class_name ChallengeGameMode extends RunnerGameMode

var _complete_toast_duration: float = 3.0
var _complete_toast_remaining: float = -1.0


func Enter(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	gamemode_manager.current_game_mode = GameModeType.Kind.CHALLENGE
	DebugUtils.DebugMsg("Challenge Mode")

	super(state_context)

	if multiplayer.is_server():
		_start_next_runner()


func Update(delta: float):
	if !multiplayer.is_server():
		return
	if _complete_toast_remaining > 0.0:
		_complete_toast_remaining -= delta
		if _complete_toast_remaining <= 0.0:
			_complete_toast_remaining = -1.0
			_return_to_free_roam()
		return
	super(delta)


func Exit(state_context: StateContext):
	if Engine.is_editor_hint():
		return
	super(state_context)
	_complete_toast_remaining = -1.0


#override
## The speech bubble is revealed by its tasks, not up front.
func shows_event_props() -> bool:
	return false


#override
func _on_last_runner_completed(_runner: TaskRunner):
	riding_hud_state.push_event_status_all("CHALLENGE_COMPLETE")
	_complete_toast_remaining = _complete_toast_duration
