@tool
## Completes when the player passes through `trigger` (a CheckPointMarker).
## Mode-agnostic — usable from race / trick courses too.
class_name CheckpointTutorialStep extends GameModeObjective

@export var objective_key: String = "TUT_CHECKPOINT"
@export var hint_key: String = "TUT_HINT_CHECKPOINT"


func _init():
	eval_when = EvalWhen.ON_ENTER


func check(_player: PlayerEntity, _delta: float, _state: Dictionary) -> bool:
	return true


func get_objective_text() -> String:
	return tr(objective_key)


func get_hint_text() -> String:
	return tr(hint_key)


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if trigger != null and !(trigger is CheckPointMarker):
		issues.append("trigger must be a CheckPointMarker")
	return issues
