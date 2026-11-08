@tool
## Turns `objects` on or off (shown, triggering and colliding, children included) on every peer,
## then auto-advances. For props a lesson needs only part of the time, e.g. the tutorial's steering
## gates, which would block the braking lesson on the same road. Author them `is_active = false`.
class_name SetActiveTask extends GameModeTask

@export var objects: Array[GameModeObject] = []
@export var active: bool = true


func on_enter(_player: PlayerEntity, _state: Dictionary) -> void:
	_rpc_set_active.rpc()


func check(_player: PlayerEntity, _delta: float, _state: Dictionary) -> bool:
	return true


@rpc("call_local", "reliable")
func _rpc_set_active():
	# Only the server runs tasks — a client RPCing this is misbehaving.
	if multiplayer.get_remote_sender_id() > 1:
		return
	for object in objects:
		object.is_active = active


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if objects.is_empty() or objects.has(null):
		issues.append("objects must be set, with no empty slots")
	return issues
