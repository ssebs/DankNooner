@tool
## The route's PickupSpawners, live only while the race runs. Held items reset at the start.
class_name PickupsComponent extends RaceComponent

@export var item_manager: ItemManager


func race_start() -> void:
	item_manager.clear_items()
	for spawner in race_mode.get_route().get_pickup_spawners():
		spawner.activate(item_manager)


func race_end() -> void:
	for spawner in race_mode.get_route().get_pickup_spawners():
		spawner.deactivate()


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if item_manager == null:
		issues.append("item_manager must not be empty")
	return issues
