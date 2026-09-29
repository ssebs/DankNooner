@tool
## One selectable event on its parent EventStartCircle: a definition, an optional EventRoute and
## the TaskRunner children the target gamemode runs, in tree order.
class_name GameModeEvent extends Node

@export var definition: GameModeEventDefinition
## Leave empty for events with no grid/checkpoints/props (tutorials).
@export var route: EventRoute


func get_circle() -> EventStartCircle:
	return get_parent()


func get_runners() -> Array[TaskRunner]:
	var out: Array[TaskRunner] = []
	for c in get_children():
		if c is TaskRunner:
			out.append(c)
	return out


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	if definition == null:
		issues.append("definition must not be empty")
	if not get_parent() is EventStartCircle:
		issues.append("parent must be an EventStartCircle")
	if get_runners().is_empty():
		issues.append("needs at least one TaskRunner child")
	var circle := get_parent() as EventStartCircle
	if definition != null and definition.fuel_up_first and circle != null and circle.gas_station == null:
		issues.append("fuel_up_first needs gas_station set on the parent EventStartCircle")
	var race_tasks := find_children("*", "RaceTask", true, false)
	var needs_route := not race_tasks.is_empty() or not find_children("*", "GridSpawnTask", true, false).is_empty()
	if needs_route and route == null:
		issues.append("route must be set — a RaceTask / GridSpawnTask reads it")
	if route == null:
		return issues
	var checkpoints := route.get_checkpoints()
	for race_task: RaceTask in race_tasks:
		if checkpoints.size() < 2:
			issues.append("route needs at least 2 CheckPointMarker children")
		elif race_task.total_laps > 1 and not "StartStop" in checkpoints[0].name:
			issues.append("lap races need the route's first CheckPointMarker named ending in \"StartStop1\"")
	return issues
