## Completes once the help menu has been closed by the player.
## TutorialGameMode opens the help menu in `_start_step_for_peer` when the
## current lesson's objective `is CloseHelpObjective`, and writes
## `state["closed"] = true` when it receives the help-closed RPC.
class_name CloseHelpObjective extends Objective


func on_enter(_player: PlayerEntity, state: Dictionary) -> void:
	state["closed"] = false


func check(_player: PlayerEntity, _delta: float, state: Dictionary) -> bool:
	return state.get("closed", false)


func get_objective_text() -> String:
	return "TUT_SHOW_HELP"


func get_hint_text() -> String:
	return "TUT_HINT_SHOW_HELP"
