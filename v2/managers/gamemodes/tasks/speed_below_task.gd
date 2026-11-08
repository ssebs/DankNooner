@tool
## Player speed (m/s) must drop below `max_speed`, e.g. braking to a stop.
class_name SpeedBelowTask extends GameModeTask

@export var max_speed: float = 1.0
@export var objective_key: String = "TUT_STOP"
@export var hint_key: String = "TUT_HINT_STOP"


func check(player: PlayerEntity, _delta: float, _state: Dictionary) -> bool:
	return player.movement_controller.speed < max_speed


func get_objective_text() -> String:
	return tr(objective_key).format({"speed": max_speed})


func get_hint_text() -> String:
	return tr(hint_key).format({"speed": max_speed})
