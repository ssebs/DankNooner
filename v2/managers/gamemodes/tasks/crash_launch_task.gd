@tool
## One heat's charge at the launch wall. Never completes: CrashLaunchGameMode measures the launches
## and ends the heat; this only gives the event pane its objective.
class_name CrashLaunchTask extends GameModeTask

@export var objective_key: String = "CRASH_LAUNCH_OBJECTIVE"


func get_objective_text() -> String:
	return tr(objective_key)
