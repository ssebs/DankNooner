@tool
## Constraint task: the player must keep performing one of `required_tricks`.
## If they go without it for longer than `grace` seconds, they're respawned at
## their last checkpoint (the persistent respawn point RaceTask keeps updated).
##
## Reusable across events and tricks — drop it into a ConcurrentTaskRunner next
## to the objective task (e.g. RaceTask) and pick the trick(s) + grace in the
## inspector. Examples: wheelie race, "stoppie through this zone", etc.
##
## is_constraint is forced on so ConcurrentTaskRunner ticks it every frame
## without it ever gating completion.
class_name MaintainTrickTask extends GameModeTask

## TrickController.Trick enum values that satisfy the constraint. GDScript can't
## type an array to an enum, so these are the raw ints (default: the two wheelie
## variants — WHEELIE_SITTING, WHEELIE_MOD).
@export var required_tricks: Array[int] = [
	TrickController.Trick.WHEELIE_SITTING,
	TrickController.Trick.WHEELIE_MOD,
]
## Seconds the player may go without the trick before being sent back.
@export var grace: float = 2.0
## Localization key for the on-HUD warning. Receives {time} = seconds remaining.
@export var warn_key: String = "RACE_WHEELIE_WARN"


func _init() -> void:
	is_constraint = true


func check(player: PlayerEntity, delta: float, state: Dictionary) -> bool:
	if player.trick_controller.current_trick in required_tricks:
		state["t"] = 0.0
		return false
	state["t"] = state.get("t", 0.0) + delta
	if state["t"] >= grace:
		DebugUtils.DebugMsg("MaintainTrickTask: peer %d lost the trick — respawning" % int(player.name))
		_runner.spawn_manager.respawn_player.rpc(int(player.name))
		state["t"] = 0.0
	return false


## Empty while the trick is held so the objective (RaceTask) keeps the HUD line;
## a countdown warning once the player is losing the hold.
func get_progress(state: Dictionary) -> String:
	var elapsed: float = state.get("t", 0.0)
	if elapsed <= 0.0:
		return ""
	return tr(warn_key).format({"time": "%.1f" % maxf(grace - elapsed, 0.0)})
