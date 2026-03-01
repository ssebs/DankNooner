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


## Override this, used to press back btn / close menu / etc when ESC is pressed
## Called from menu_manager when ui_cancel is pressed
func on_cancel_key_pressed():
	pass


func get_first_button_for_focus() -> Button:
	var buttons = find_children("*", "Button", true, true)
	if len(buttons) == 0:
		return null
	return buttons[0]
