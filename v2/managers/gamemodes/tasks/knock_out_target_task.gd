@tool
## Knock `target`, a level-placed NPC rider, off its bike (e.g. with the shotgun). A parked NPC's
## idle state ignores hits, so from this step on a hit crashes it. It stays down.
class_name KnockOutTargetTask extends GameModeTask

@export var target: NPCRiderEntity
@export var objective_key: String = "TUT_KNOCK_OUT"


func on_enter(_player: PlayerEntity, _state: Dictionary) -> void:
	# Every peer on this step shares the one target — already connected is intentional
	if !target.hit_by_racer.is_connected(_on_target_hit):
		target.hit_by_racer.connect(_on_target_hit)


func check(_player: PlayerEntity, _delta: float, _state: Dictionary) -> bool:
	return target.is_crashed


func get_objective_text() -> String:
	return tr(objective_key)


func _on_target_hit(_hitter: Node3D) -> void:
	target.crash()


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if target == null:
		issues.append("target must not be empty")
	return issues
