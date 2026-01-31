@tool
## Manages other managers (init, etc.)
## Other managers should be nested under this node
## All children will be added to the "Managers" Group
class_name ManagerManager extends Node

func _ready():
    for child in get_children():
        child.add_to_group(UtilsConstants.GROUPS["Managers"], true)
