@tool
## Completes when the player passes through `trigger` (a CheckPointMarker or TriggerZone).
## Mode-agnostic — usable from race / trick courses too.
class_name CheckpointTask extends GameModeTask

@export var objective_key: String = "TUT_CHECKPOINT"
## Hide `trigger` from each rider once they pass it; restarting the step shows it again.
@export var hide_trigger_on_pass: bool = false
## Warn (never respawn) a rider this many meters past their closest approach to `trigger` and
## still heading away, like RaceTask. 0 is off; needs eval_when ALWAYS to watch every frame.
@export var wrong_way_margin: float = 0.0

## Peers currently shown the wrong-way warning. Not the scratchpad: a crash wipes that, and the
## warning would stick.
var _wrong_way_peers: Dictionary[int, bool] = {}


func _init():
	eval_when = EvalWhen.ON_ENTER


func on_enter(player: PlayerEntity, _state: Dictionary) -> void:
	if hide_trigger_on_pass:
		trigger.rpc_set_shown.rpc_id(int(player.name), true)


func check(player: PlayerEntity, _delta: float, state: Dictionary) -> bool:
	if wrong_way_margin > 0.0:
		_check_wrong_way(player, state)
	# ALWAYS reads the crossing from the scratchpad; ON_ENTER only runs on it.
	return eval_when == EvalWhen.ON_ENTER or state.has("trigger_entered")


func on_exit(player: PlayerEntity, _state: Dictionary) -> void:
	if hide_trigger_on_pass:
		trigger.rpc_set_shown.rpc_id(int(player.name), false)
	var peer_id := int(player.name)
	if _wrong_way_peers.has(peer_id):
		_wrong_way_peers.erase(peer_id)
		runner.riding_hud.clear_event_warning(peer_id)


func get_objective_text() -> String:
	return tr(objective_key)


func _check_wrong_way(player: PlayerEntity, state: Dictionary) -> void:
	var peer_id := int(player.name)
	var wrong_way := RaceTask.is_wrong_way(player, trigger.global_position, wrong_way_margin, state)
	if wrong_way == _wrong_way_peers.has(peer_id):
		return
	if wrong_way:
		_wrong_way_peers[peer_id] = true
		runner.riding_hud.push_event_warning(peer_id, "RACE_WRONG_WAY", true)
	else:
		_wrong_way_peers.erase(peer_id)
		runner.riding_hud.clear_event_warning(peer_id)


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if trigger != null and !(trigger is CheckPointMarker or trigger is TriggerZone):
		issues.append("trigger must be a CheckPointMarker or TriggerZone")
	if wrong_way_margin > 0.0 and eval_when != EvalWhen.ALWAYS:
		issues.append("wrong_way_margin needs eval_when ALWAYS")
	return issues
