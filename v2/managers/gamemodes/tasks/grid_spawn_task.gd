@tool
## Assigns each entering peer the next slot from its Marker3D children (in tree
## order) and teleports them there, also storing that transform as their persistent respawn point
## (same mechanism as TeleportTask). Auto-advances.
##
## If there are more peers than markers, extras stack on the last marker —
## collision-avoidance handles separation.
class_name GridSpawnTask extends GameModeTask

## Signpost only — assign the first grid Marker3D so a fresh node shows in the inspector that
## Marker3D children are expected. The live set is auto-collected from the children (on_enter).
@export var first_grid_marker: Marker3D

var _next_slot: int = 0


## The grid slots, in tree order — the Marker3D children of this task. Recomputes on each call.
func get_grid_markers() -> Array[Marker3D]:
	var markers: Array[Marker3D] = []
	markers.assign(find_children("*", "Marker3D", false))
	return markers


func on_enter(player: PlayerEntity, _state: Dictionary) -> void:
	var grid_markers := get_grid_markers()
	var peer_id := int(player.name)
	var idx: int = min(_next_slot, grid_markers.size() - 1)
	var marker := grid_markers[idx]
	_runner.spawn_manager.respawn_player_at.rpc(
		peer_id, marker.global_position, marker.global_basis
	)
	_next_slot += 1


func check(_player: PlayerEntity, _delta: float, _state: Dictionary) -> bool:
	return true


func on_exit(_player: PlayerEntity, _state: Dictionary) -> void:
	# Reset once everyone has passed through, so the next race starts at slot 0.
	_next_slot = max(0, _next_slot - 1)


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	var grid_markers := get_grid_markers()
	if first_grid_marker == null:
		issues.append("assign first_grid_marker — Marker3D children are required (auto-collected at runtime)")
	elif not grid_markers.is_empty() and not grid_markers[0].name.ends_with("1"):
		issues.append("first Marker3D should be named ending in \"1\" so they count up")
	return issues
