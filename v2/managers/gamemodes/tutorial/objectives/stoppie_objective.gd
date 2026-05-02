## Hold a stoppie for `duration` seconds.
class_name StoppieObjective extends Objective

@export var duration: float = 1.0


func check(player: PlayerEntity, delta: float, state: Dictionary) -> bool:
	var is_stoppie := player.trick_controller.current_trick == TrickController.Trick.STOPPIE
	if !is_stoppie:
		state["t"] = 0.0
		return false
	state["t"] = state.get("t", 0.0) + delta
	return state["t"] >= duration


func get_progress(state: Dictionary) -> String:
	return "%s\n%.1f / %.1fs" % [tr("TUT_HINT_DO_STOPPIE"), state.get("t", 0.0), duration]


func get_objective_text() -> String:
	return "TUT_DO_STOPPIE"


func get_hint_text() -> String:
	return "TUT_HINT_DO_STOPPIE"
