## Records the player's gear on first eval, completes once it changes.
class_name ChangeGearObjective extends Objective


func on_enter(_player: PlayerEntity, state: Dictionary) -> void:
	state["initial"] = -1


func check(player: PlayerEntity, _delta: float, state: Dictionary) -> bool:
	var initial: int = state.get("initial", -1)
	if initial == -1:
		state["initial"] = player.gearing_controller.current_gear
		return false
	return player.gearing_controller.current_gear != initial


func get_objective_text() -> String:
	return "TUT_CHANGE_GEAR"


func get_hint_text() -> String:
	return "TUT_HINT_CHANGE_GEAR"
