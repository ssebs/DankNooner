@tool
## Player speed (m/s) must exceed `min_speed`. Reused for PRESS_RT (low threshold)
## and REACH_SPEED (higher threshold) — text keys are configurable per instance.
class_name SpeedAboveTask extends GameModeTask

@export var min_speed: float = 20.0
@export var objective_key: String = "TUT_REACH_SPEED"
@export var hint_key: String = "TUT_HINT_REACH_SPEED"


func check(player: PlayerEntity, _delta: float, _state: Dictionary) -> bool:
	return player.movement_controller.speed > min_speed


func get_objective_text() -> String:
	return tr(objective_key).format({"speed": min_speed})


func get_hint_text() -> String:
	return tr(hint_key).format({"speed": min_speed})
