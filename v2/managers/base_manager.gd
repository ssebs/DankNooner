@tool
## For all managers except manager_manager
class_name BaseManager extends Node

var manager_manager: ManagerManager


func _ready():
	add_to_group(UtilsConstants.GROUPS["Validate"])
