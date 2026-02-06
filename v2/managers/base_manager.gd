@tool
## For all managers except manager_manager
class_name BaseManager extends Node

var manager_manager: ManagerManager


func _ready():
	add_to_group(UtilsConstants.GROUPS["Validate"])


func disable_input_and_processing():
	set_process_unhandled_input(false)
	set_process_input(false)
	set_process(false)
	set_physics_process(false)


func enable_input_and_processing():
	set_process_unhandled_input(true)
	set_process_input(true)
	set_process(true)
	set_physics_process(true)
