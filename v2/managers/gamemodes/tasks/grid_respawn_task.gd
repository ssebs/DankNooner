@tool
## Respawns each entering peer to a slot from a referenced GridSpawnTask's
## grid_markers. Auto-advances. Used to reset players to the grid between
## stages of a challenge (e.g. before each trick step).
##
## Slots cycle independently of the source GridSpawnTask's counter — peers
## entering this task get assigned starting from slot 0 each pass.
class_name GridRespawnTask extends GameModeTask

@export var grid_spawn_task: GridSpawnTask

var _next_slot: int = 0


func on_enter(player: PlayerEntity, _state: Dictionary) -> void:
	var peer_id := int(player.name)
	var markers := grid_spawn_task.grid_markers
	var idx: int = min(_next_slot, markers.size() - 1)
	var marker := markers[idx]
	_runner.spawn_manager.respawn_player_at.rpc(
		peer_id, marker.global_position, marker.global_basis
	)
	_next_slot += 1


func check(_player: PlayerEntity, _delta: float, _state: Dictionary) -> bool:
	return true


func on_exit(_player: PlayerEntity, _state: Dictionary) -> void:
	_next_slot = max(0, _next_slot - 1)


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if grid_spawn_task == null:
		issues.append("grid_spawn_task must be set")
	elif grid_spawn_task.grid_markers.is_empty():
		issues.append("referenced grid_spawn_task has no markers")
	return issues
