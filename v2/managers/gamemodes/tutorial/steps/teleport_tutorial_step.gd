@tool
## Checkpoint step: teleports the player to `marker` on enter, registers it as the
## per-peer respawn point for subsequent crashes, and auto-advances. Useful for
## breaking long courses into sections so a crash doesn't send players all the
## way back to the start.
class_name TeleportTutorialStep extends GameModeObjective

@export var marker: Marker3D


func on_enter(player: PlayerEntity, _state: Dictionary) -> void:
	var tut := _gamemode as TutorialGameMode
	var peer_id := int(player.name)
	tut.set_respawn_marker(peer_id, marker)
	tut.spawn_manager.respawn_player_at.rpc(peer_id, marker.global_position, marker.global_basis)


func check(_player: PlayerEntity, _delta: float, _state: Dictionary) -> bool:
	return true


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if marker == null:
		issues.append("marker must be set")
	return issues
