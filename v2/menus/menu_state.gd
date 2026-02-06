@tool
## All Menu objects should inherit from this
class_name MenuState extends State

@onready var ui: Control = %UI


func _ready():
	add_to_group(UtilsConstants.GROUPS["Validate"])


func hide_ui():
	ui.hide()


func show_ui():
	ui.show()


# ON UI BACK, NAV to PREV


func get_first_button_for_focus() -> Button:
	var buttons = find_children("*", "Button", true, true)
	if len(buttons) == 0:
		return null
	return buttons[0]
