@tool
## The physical side of an event: grid slots (Marker3D), the CheckPointMarker route and
## PickupSpawners as direct children, each group in tree order, plus props (arrow walls, ramps).
## Lives under an EventStartCircle; several GameModeEvents on that circle can share one.
##
## top_level so the route sits in world space, whatever the circle's transform.
class_name EventRoute extends Node3D


func _init():
	top_level = true


## Grid slots in tree order. PickupSpawner is a Marker3D too — excluded.
func get_grid_markers() -> Array[Marker3D]:
	var markers: Array[Marker3D] = []
	for child in get_children():
		if child is Marker3D and not child is PickupSpawner:
			markers.append(child)
	return markers


func get_checkpoints() -> Array[CheckPointMarker]:
	var checkpoints: Array[CheckPointMarker] = []
	checkpoints.assign(find_children("*", "CheckPointMarker", false))
	return checkpoints


## Client-local: only the racer's upcoming gates are shown; the one just passed flashes out.
func show_only_checkpoints(shown: PackedInt32Array, passed_idx: int = -1):
	var checkpoints := get_checkpoints()
	for i in checkpoints.size():
		if i in shown:
			checkpoints[i].reset_passed()
		elif i == passed_idx:
			checkpoints[i].play_passed()
		else:
			checkpoints[i].visible = false


func get_pickup_spawners() -> Array[PickupSpawner]:
	var spawners: Array[PickupSpawner] = []
	spawners.assign(find_children("*", "PickupSpawner", false))
	return spawners


## Show + collide only while one of its events runs — a hidden prop mustn't be an invisible wall.
func set_active(active: bool):
	visible = active
	for obj in find_children("*", "GameModeObject", true, false):
		obj.is_active = active
	for shape in find_children("*", "CollisionShape3D", true, false):
		shape.disabled = not active


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	# Tree order is the sequence, so names should count up from 1.
	var firsts := {
		"Marker3D": get_grid_markers(),
		"CheckPointMarker": get_checkpoints(),
		"PickupSpawner": get_pickup_spawners(),
	}
	for type_name in firsts:
		var group: Array = firsts[type_name]
		if not group.is_empty() and not group[0].name.ends_with("1"):
			issues.append("first %s should be named ending in \"1\" so they count up" % type_name)
	return issues
