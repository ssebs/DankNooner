@tool
## Hold a wheelie (sitting or mod) for `duration` seconds.
class_name WheelieDurationTask extends GameModeTask

@export var duration: float = 2.0


func check(player: PlayerEntity, delta: float, state: Dictionary) -> bool:
	var is_wheelie := (
		player.trick_controller.current_trick
		in [TrickController.Trick.WHEELIE_SITTING, TrickController.Trick.WHEELIE_MOD]
	)
	if !is_wheelie:
		state["t"] = 0.0
		return false
	state["t"] = state.get("t", 0.0) + delta
	return state["t"] >= duration


func get_progress(state: Dictionary) -> String:
	return "%s\n%.1f / %.1fs" % [tr("TUT_HINT_DO_WHEELIE"), state.get("t", 0.0), duration]


func get_objective_text() -> String:
	return tr("TUT_DO_WHEELIE").format({"duration": duration})


func get_hint_text() -> String:
	return tr("TUT_HINT_DO_WHEELIE")
