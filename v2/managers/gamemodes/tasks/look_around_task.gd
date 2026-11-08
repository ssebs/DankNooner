@tool
## Look around (camera stick or mouse) for `duration` seconds in total. Solo only: the mouse isn't
## netcode input, so it's read from the server's own Input, which is the rider's in the tutorial.
class_name LookAroundTask extends GameModeTask

@export var duration: float = 1.0
@export var objective_key: String = "TUT_LOOK_AROUND"

## Mouse speed (px/s) that counts as looking.
const MOUSE_LOOK_SPEED: float = 100.0


func check(player: PlayerEntity, delta: float, state: Dictionary) -> bool:
	var input := player.input_controller
	var stick := Vector2(input.nfx_cam_x, input.nfx_cam_y).length() > 0.5
	var mouse := Input.get_last_mouse_velocity().length() > MOUSE_LOOK_SPEED
	if stick or mouse:
		state["t"] = state.get("t", 0.0) + delta
	return state.get("t", 0.0) >= duration


func get_progress(state: Dictionary) -> String:
	return "%.1f / %.1fs" % [state.get("t", 0.0), duration]


func get_objective_text() -> String:
	return tr(objective_key)
