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
	_task.hide_trigger_on_pass = true
	_task.respawn_in_place = true
	# Every frame, to watch for the wrong way
	_task.eval_when = GameModeTask.EvalWhen.ALWAYS
	_task.wrong_way_margin = 40.0
	add_child(_task)


#override
func wire_task_refs() -> void:
	_task.trigger = event.start_zone
	super()
