@tool
## Knock `target`, a level-placed NPC rider, off its bike (e.g. with the shotgun). A parked NPC's
## idle state ignores hits, so from this step on a hit crashes it. It stays down.
## Using the held item without dropping the target sends the rider back to their respawn point.
class_name KnockOutTargetTask extends GameModeTask

@export var target: NPCRiderEntity
@export var objective_key: String = "TUT_KNOCK_OUT"

## Injected by TutorialGameMode.
var item_manager: ItemManager


func on_enter(_player: PlayerEntity, _state: Dictionary) -> void:
	# Every peer on this step shares the one target — already connected is intentional
	if !target.hit_by_racer.is_connected(_on_target_hit):
		target.hit_by_racer.connect(_on_target_hit)


func check(player: PlayerEntity, _delta: float, state: Dictionary) -> bool:
	if target.is_crashed:
		return true
	var peer_id := int(player.name)
	if item_manager.get_held(peer_id) != null:
		state["armed"] = true
	elif state.has("armed"):
		# A hit crashes the target in the same call that empties the slot, so this is a miss.
		state.clear()
		runner.riding_hud.push_event_warning(peer_id, "TUT_SHOTGUN_TOO_FAR")
		runner.spawn_manager.respawn_player.rpc(peer_id)
	return false


func get_objective_text() -> String:
	return tr(objective_key)


func _on_target_hit(_hitter: Node3D) -> void:
	target.crash()


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if target == null:
		issues.append("target must not be empty")
	return issues
