@tool
## One selectable event on its parent EventStartCircle: a definition, links to the circle's groups
## it uses, and the TaskRunner children the target gamemode runs, in tree order. See
## EventStartCircle for the layout.
class_name GameModeEvent extends Node3D

@export var definition: GameModeEventDefinition
## Groups under the circle's Props, shown + collided only while this event runs.
@export var props: Array[Node3D] = []
## A group under the circle's Spawns. Its Marker3D children are the grid slots, in tree order.
@export var spawn: Node3D
## A group under the circle's Checkpoints. Its CheckPointMarker children are the race route, in
## tree order.
@export var checkpoints: Node3D
## This event's own child holding its PickupSpawners. Leave empty for none (time attack).
@export var pickups: Node3D
## Where a DriveToStartRunner sends riders. Fires while this event runs, hidden until that runner
## shows it.
@export var start_zone: TriggerZone


func get_circle() -> EventStartCircle:
	return get_parent()


func get_runners() -> Array[TaskRunner]:
	var out: Array[TaskRunner] = []
	for c in get_children():
		if c is TaskRunner:
			out.append(c)
	return out


func get_spawn_markers() -> Array[Marker3D]:
	var markers: Array[Marker3D] = []
	markers.assign(spawn.find_children("*", "Marker3D", false))
	return markers


func get_checkpoints() -> Array[CheckPointMarker]:
	var out: Array[CheckPointMarker] = []
	out.assign(checkpoints.find_children("*", "CheckPointMarker", false))
	return out


func get_pickup_spawners() -> Array[PickupSpawner]:
	var spawners: Array[PickupSpawner] = []
	# Time attacks run the pickups component with no pickups — empty is intentional
	if pickups != null:
		spawners.assign(pickups.find_children("*", "PickupSpawner", false))
	return spawners


## Client-local: only the racer's upcoming gates are shown; the one just passed flashes out.
func show_only_checkpoints(shown: PackedInt32Array, passed_idx: int = -1):
	var gates := get_checkpoints()
	for i in gates.size():
		if i in shown:
			gates[i].reset_passed()
		elif i == passed_idx:
			gates[i].play_passed()
		else:
			gates[i].visible = false


## Called by the circle when this event starts / ends.
func set_active(active: bool):
	set_props_active(active)
	if start_zone != null:
		start_zone.is_active = active
		start_zone.visible = false


## Everything but the start zone, so the drive to the start can hide the race's props.
func set_props_active(active: bool):
	for group in props + [checkpoints, pickups]:
		# Non-race events leave checkpoints / pickups empty
		if group != null:
			get_circle().set_group_active(group, active)


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	if definition == null:
		issues.append("definition must not be empty")
	if not get_parent() is EventStartCircle:
		issues.append("parent must be an EventStartCircle")
	var runners := get_runners()
	if runners.is_empty():
		issues.append("needs at least one TaskRunner child")
	var circle := get_parent() as EventStartCircle
	if definition != null and definition.fuel_up_first and circle != null and circle.gas_station == null:
		issues.append("fuel_up_first needs gas_station set on the parent EventStartCircle")
	if props.has(null):
		issues.append("props has an empty slot")

	var race_tasks := find_children("*", "RaceTask", true, false)
	var grid_tasks := find_children("*", "GridSpawnTask", true, false)
	grid_tasks.append_array(find_children("*", "GridRespawnTask", true, false))
	if spawn == null and not (race_tasks.is_empty() and grid_tasks.is_empty()):
		issues.append("spawn must be set — a RaceTask / GridSpawnTask / GridRespawnTask reads it")
	if spawn != null and get_spawn_markers().size() < UtilsConstants.MAX_LOBBY_SIZE:
		issues.append("spawn needs %d Marker3D children, one per rider" % UtilsConstants.MAX_LOBBY_SIZE)
	if not race_tasks.is_empty():
		if checkpoints == null:
			issues.append("checkpoints must be set — a RaceTask reads it")
		if pickups == null and definition != null and definition.target_gamemode == GameModeType.Kind.STUNT_RACE:
			issues.append("pickups must be set for a stunt race")
	var has_drive_to_start := not find_children("*", "DriveToStartRunner", true, false).is_empty()
	if start_zone == null and has_drive_to_start:
		issues.append("start_zone must be set — the DriveToStartRunner drives to it")
	if start_zone != null and not has_drive_to_start:
		issues.append("start_zone is set but nothing drives to it — add a DriveToStartRunner")

	# Tree order is the sequence, so names should count up from 1.
	var firsts := {"spawn": spawn, "checkpoints": checkpoints, "pickups": pickups}
	for export_name in firsts:
		var group: Node3D = firsts[export_name]
		if group != null and group.get_child_count() > 0 and not group.get_child(0).name.ends_with("1"):
			issues.append("first child of %s should be named ending in \"1\" so they count up" % export_name)

	if checkpoints == null:
		return issues
	var gates := get_checkpoints()
	for race_task: RaceTask in race_tasks:
		if gates.size() < 2:
			issues.append("checkpoints needs at least 2 CheckPointMarker children")
		elif race_task.total_laps > 1 and not RaceTask.is_lap_route(gates):
			issues.append("lap races need the first CheckPointMarker named ending in \"StartStop1\"")
	return issues
