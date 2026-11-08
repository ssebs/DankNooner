@tool
## Push the camera stick (any direction) for `duration` seconds in total.
class_name LookAroundTask extends GameModeTask

@export var duration: float = 1.0
@export var objective_key: String = "TUT_LOOK_AROUND"


func check(player: PlayerEntity, delta: float, state: Dictionary) -> bool:
	var input := player.input_controller
	if Vector2(input.nfx_cam_x, input.nfx_cam_y).length() > 0.5:
		state["t"] = state.get("t", 0.0) + delta
	return state.get("t", 0.0) >= duration


func get_progress(state: Dictionary) -> String:
	return "%.1f / %.1fs" % [state.get("t", 0.0), duration]


func get_objective_text() -> String:
	return tr(objective_key)
