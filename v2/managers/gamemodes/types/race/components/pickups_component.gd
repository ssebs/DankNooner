@tool
## The route's PickupSpawners, live only while the race runs.
class_name PickupsComponent extends RaceComponent


func race_start() -> void:
	for spawner in race_mode.get_route().get_pickup_spawners():
		spawner.activate(race_mode.spawn_manager)


func race_end() -> void:
	for spawner in race_mode.get_route().get_pickup_spawners():
		spawner.deactivate()
