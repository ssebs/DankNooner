@tool
class_name MenuManager extends BaseManager

@export var state_machine: StateMachine
@export var pause_menu_state: MenuState

@export var is_verbose: bool = false

var prev_state: MenuState


func _ready():
	hide_all_menus()

	if Engine.is_editor_hint():
		return

	state_machine.state_transitioned.connect(_on_state_transitioned)


func _on_state_transitioned(old_state: State, new_state: State):
	prev_state = old_state
	grab_focus_to_first_btn(new_state)


## Load pause_menu_state as current state
func switch_to_pause_menu():
	state_machine.request_state_change(pause_menu_state, null, true)


## Focuses the top btn so the player can control w/ controller
func grab_focus_to_first_btn(m_state: MenuState):
	var btn = m_state.get_first_button_for_focus()
	if btn == null:
		if is_verbose:
			print("Could not find btn")
		return

	btn.grab_focus()


## Will hide all menus
## stays in current menu state
func hide_all_menus():
	for child in state_machine.get_children():
		if !child is MenuState:
			continue
		child.hide_ui()
