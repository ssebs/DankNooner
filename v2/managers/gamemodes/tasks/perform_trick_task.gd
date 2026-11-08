@tool
## Perform a specific trick, optionally for a minimum duration and/or ending inside a zone.
##
## Works for both duration tricks (wheelie, stoppie) and instantaneous tricks
## (heel_clicker, high_chair) — set `min_duration = 0` for instant.
##
## When used in a challenge, set `eval_when = WHILE_INSIDE` and `trigger` to a
## TriggerZone so progress only accumulates while the player is inside.
##
## `must_land` holds the pass until the trick is over and the rider is back on the ground, so a
## following step (e.g. a tutorial tour) doesn't cut the trick off. A crash clears it.
class_name PerformTrickTask extends GameModeTask

@export var required_trick: TrickController.Trick = TrickController.Trick.WHEELIE_SITTING
@export var min_duration: float = 0.0
@export var success_zone: Area3D = null
@export var must_land: bool = false
## Localization keys (optional — fall back to a generic label if empty).
@export var objective_key: String = ""
@export var hint_key: String = ""


func check(player: PlayerEntity, delta: float, state: Dictionary) -> bool:
	if state.get("trick_done", false):
		return (
			!player.is_crashed
			and player.movement_controller.is_on_floor
			and player.trick_controller.current_trick == TrickController.Trick.NONE
		)
	var active := player.trick_controller.current_trick == required_trick
	if !active:
		state["t"] = 0.0
		return false
	state["t"] = state.get("t", 0.0) + delta
	if state["t"] < min_duration:
		return false
	if success_zone != null and !success_zone.overlaps_body(player):
		return false
	if must_land:
		state["trick_done"] = true
		return false
	return true


func get_progress(state: Dictionary) -> String:
	if state.get("trick_done", false):
		return tr("TUT_LAND_TRICK")
	if min_duration <= 0.0:
		return get_hint_text()
	return "%.1f / %.1fs" % [state.get("t", 0.0), min_duration]


func get_objective_text() -> String:
	if objective_key != "":
		return tr(objective_key).format({"duration": min_duration})
	return tr("TRICK_NAME_" + TrickController.trick_to_str(required_trick))


func get_hint_text() -> String:
	if hint_key != "":
		return tr(hint_key)
	return ""


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if required_trick == TrickController.Trick.NONE:
		issues.append("required_trick must not be NONE")
	return issues
