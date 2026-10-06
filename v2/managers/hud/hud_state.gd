@tool
class_name HUDState extends State

@onready var ui: Control = %UI


func hide_ui():
	ui.hide()


func show_ui():
	ui.show()


## Override this, called from InputStateManager on ui_cancel during IN_MINIGAME
func on_cancel_key_pressed():
	pass


## Override this, called from InputStateManager during IN_MINIGAME. `dir` is -1 or 1
func on_tab_key_pressed(_dir: int):
	pass
