@tool
class_name MenuManager extends Node

@export var state_machine: StateMachine

var prev_state: MenuState


func _ready():
	hide_all_menus()

	if Engine.is_editor_hint():
		return

	state_machine.state_transitioned.connect(_on_state_transitioned)


func _on_state_transitioned(old_state: State, _new_state: State):
	prev_state = old_state


## Will hide all menus
func hide_all_menus():
	for child in state_machine.get_children():
		if !child is MenuState:
			continue
		child.hide_ui()
