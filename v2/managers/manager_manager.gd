@tool
## Manages other managers (init, etc.)
## Other managers should be nested under this node
## All children will be added to the "Managers" Group
class_name ManagerManager extends Node

var level_manager: LevelManager
var menu_manager: MenuManager
var pause_manager: PauseManager


func _ready():
	for child in get_children():
		if !child is BaseManager:
			continue

		if child is LevelManager:
			level_manager = child
		elif child is MenuManager:
			menu_manager = child
		elif child is PauseManager:
			pause_manager = child

		child.add_to_group(UtilsConstants.GROUPS["Managers"], true)
		child.manager_manager = self
