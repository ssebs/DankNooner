@tool
## Drives every rider to the event's start_zone before the race. Builds its own CheckpointTask, so
## the level only places this node (before the race's runner) and links start_zone on the event.
class_name DriveToStartRunner extends SequentialTaskRunner

var _task: CheckpointTask


func _ready():
	if Engine.is_editor_hint():
		return
	# Same name on every peer, so RPCs by path resolve.
	_task = CheckpointTask.new()
	_task.name = "DriveToStartTask"
	_task.objective_key = "RACE_DRIVE_TO_START"
	_task.hint_key = "RACE_HINT_DRIVE_TO_START"
	_task.hide_trigger_on_pass = true
	_task.respawn_in_place = true
	add_child(_task)


#override
func wire_task_refs() -> void:
	_task.trigger = event.start_zone
	super()
