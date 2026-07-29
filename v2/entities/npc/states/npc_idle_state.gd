@tool
## Parked rider: coast to a stop and stay on the ground. This is where clients
## sit (their state machine's physics is off anyway) and where a freshly spawned
## bot waits until its manager moves it into race or traffic.
class_name NPCIdleState extends State

@export var npc: NPCRiderEntity


func Physics_Update(delta: float):
	if Engine.is_editor_hint():
		return
	npc.coast_to_stop(delta)
	npc.apply_gravity_and_move(delta)


func _get_configuration_warnings() -> PackedStringArray:
	var issues := PackedStringArray()
	if npc == null:
		issues.append("npc must not be empty")
	return issues
