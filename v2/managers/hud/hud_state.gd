@tool
class_name HUDState extends State

@onready var ui: Control = %UI


func hide_ui():
	ui.hide()


func show_ui():
	ui.show()
