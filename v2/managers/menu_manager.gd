@tool
class_name MenuManager extends BaseManager

@export var state_machine: StateMachine

var prev_state: MenuState


func _ready():
	hide_all_menus()

	if Engine.is_editor_hint():
		return

	state_machine.state_transitioned.connect(_on_state_transitioned)


func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("ui_cancel"):
		state_machine.current_state.on_cancel_key_pressed()


func _on_state_transitioned(old_state: State, new_state: State):
	prev_state = old_state
	grab_focus_to_first_btn(new_state)


## Focuses the top btn so the player can control w/ controller
func grab_focus_to_first_btn(m_state: MenuState):
	print("grab_focus_to_first_btn")
	var btn = m_state.get_first_button_for_focus()
	if btn == null:
		print("Could not find btn")
		return

	btn.grab_focus()


## Will hide all menus
func hide_all_menus():
	for child in state_machine.get_children():
		if !child is MenuState:
			continue
		child.hide_ui()
