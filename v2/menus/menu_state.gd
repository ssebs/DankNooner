@tool
## All Menu objects should inherit from this
class_name MenuState extends State

@onready var ui: Control = %UI


func hide_ui():
	ui.hide()


func show_ui():
	ui.show()
