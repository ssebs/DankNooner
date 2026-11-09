@tool
## Boost until the meter is spent (under one segment, which can't be burned).
##
## `fill_meter` tops the meter up first, so the rider always has a full burn to try.
## `burn_all` off completes once any burn ends (one segment is a full second of boost).
class_name BoostTask extends GameModeTask

@export var fill_meter: bool = false
@export var burn_all: bool = true
@export var objective_key: String = "TUT_BURN_BOOST"


func check(player: PlayerEntity, _delta: float, state: Dictionary) -> bool:
	var boost := player.boost_controller
	# Here, not on_enter: a crash clears the scratchpad, so a rider who crashed mid-burn gets refilled.
	if fill_meter and !state.has("filled"):
		state["filled"] = true
		runner.spawn_manager.max_boost_player.rpc(int(player.name))
	if boost.is_boosting:
		state["boosted"] = true
	if !state.has("boosted") or boost.is_boosting:
		return false
	return !burn_all or boost.boost_amount < 1.0


func get_objective_text() -> String:
	return tr(objective_key)
