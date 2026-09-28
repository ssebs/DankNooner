@tool
## Endless jump attempts, each scored by the trick points it banks after passing `trigger` (the
## start gate). An attempt ends `reset_delay` seconds after landing, once its combo has banked: the
## score is reported and the rider goes back to their grid slot. A crash voids it (the runner
## respawns them there). Never completes — LongJumpGameMode owns the session clock and the ranking.
class_name LongJumpTask extends GameModeTask

signal attempt_scored(peer_id: int, points: float)

## Seconds on the ground after landing before the attempt is scored and reset.
@export var reset_delay: float = 2.0
@export var objective_key: String = "LONG_JUMP_OBJECTIVE"

## Injected by LongJumpGameMode.
var trick_manager: TrickManager


func check(player: PlayerEntity, delta: float, state: Dictionary) -> bool:
	var peer_id := int(player.name)
	# The scratchpad is empty after a reset or crash, so every attempt re-passes the gate.
	if !state.get("trigger_entered", false):
		return false
	if !state.has("jumped"):
		trick_manager.reset_peer(peer_id)
		state["jumped"] = false
		state["landed_t"] = 0.0

	if !state["jumped"]:
		state["jumped"] = (
			player.movement_controller._air_time >= TrickController.AIR_TRICK_MIN_AIRTIME
		)
		return false
	if !player.is_on_floor():
		return false

	state["landed_t"] += delta
	if state["landed_t"] < reset_delay or trick_manager.is_combo_open(peer_id):
		return false
	attempt_scored.emit(peer_id, trick_manager.get_score(peer_id))
	_runner.spawn_manager.respawn_player.rpc(peer_id)
	state.clear()
	return false


func get_objective_text() -> String:
	return tr(objective_key)


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if !(trigger is CheckPointMarker):
		issues.append("trigger must be the start gate CheckPointMarker")
	return issues
