@tool
## Completes when the player passes through `trigger` (a CheckPointMarker or TriggerZone).
## Mode-agnostic — usable from race / trick courses too.
class_name CheckpointTask extends GameModeTask

@export var objective_key: String = "TUT_CHECKPOINT"
@export var hint_key: String = "TUT_HINT_CHECKPOINT"
## Hide `trigger` from each rider once they pass it; restarting the step shows it again.
@export var hide_trigger_on_pass: bool = false


func _init():
	eval_when = EvalWhen.ON_ENTER


func on_enter(player: PlayerEntity, _state: Dictionary) -> void:
	if hide_trigger_on_pass:
		trigger.rpc_set_shown.rpc_id(int(player.name), true)


func check(_player: PlayerEntity, _delta: float, _state: Dictionary) -> bool:
	return true


func on_exit(player: PlayerEntity, _state: Dictionary) -> void:
	if hide_trigger_on_pass:
		trigger.rpc_set_shown.rpc_id(int(player.name), false)


func get_objective_text() -> String:
	return tr(objective_key)


func get_hint_text() -> String:
	return tr(hint_key)


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if trigger != null and !(trigger is CheckPointMarker or trigger is TriggerZone):
		issues.append("trigger must be a CheckPointMarker or TriggerZone")
	return issues
