@tool
## Assigns each entering peer the next slot from `grid_markers` and teleports
## them there, also storing that transform as their persistent respawn point
## (same mechanism as TeleportTask). Auto-advances.
##
## If there are more peers than markers, extras stack on the last marker —
## collision-avoidance handles separation.
class_name GridSpawnTask extends GameModeTask

@export var grid_markers: Array[Marker3D] = []

var _next_slot: int = 0


func on_enter(player: PlayerEntity, _state: Dictionary) -> void:
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
	if grid_markers.is_empty():
		issues.append("grid_markers must have at least one marker")
	return issues
