@tool
## Clean-fill bonus from the pre-race fuel-up, banked by FuelUpGameMode.
class_name FuelUpBonusComponent extends RaceComponent

@export var fuel_up_mode: FuelUpGameMode


func score(peer_id: int) -> float:
	# The bank holds the last fuel-up run, which is this race's only if it fueled up first.
	if !race_mode.get_definition().fuel_up_first:
		return 0.0
	return fuel_up_mode.get_bonus(peer_id)


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if fuel_up_mode == null:
		issues.append("fuel_up_mode must not be empty")
	return issues
