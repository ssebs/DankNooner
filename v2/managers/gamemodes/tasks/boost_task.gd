@tool
## Boost until the meter is spent (under one segment, which can't be burned).
##
## `fill_meter` tops the meter up first, so the rider always has a full burn to try.
## `burn_all` off completes on the first boost instead.
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
		if !burn_all:
			return true
		state["boosted"] = true
	return state.has("boosted") and !boost.is_boosting and boost.boost_amount < 1.0


func get_objective_text() -> String:
	return tr(objective_key)
