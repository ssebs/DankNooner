@tool
class_name HUDManager extends BaseManager

@export var state_machine: StateMachine

@export var null_hud_state: HUDState
@export var riding_hud_state: RidingHUDState

var local_player: PlayerEntity

func _ready() -> void:
	pass

func go_to_riding_hud():
	state_machine.request_state_change(riding_hud_state)


## Reset to the no-HUD state when leaving gameplay for a menu — stops RidingHUDState from
## polling controllers on a player entity that's being freed. Called from LevelManager.
func go_to_null_hud():
	state_machine.request_state_change(null_hud_state)


## Pause hides the HUD without leaving the current state, so unpause restores it without
## a full state transition. RidingHUDState.show_ui() is re-entry-safe for this.
func set_hud_hidden(hidden: bool):
	var hud_state := state_machine.current_state as HUDState
	if hidden:
		hud_state.hide_ui()
	else:
		hud_state.show_ui()


func hide_all():
	for child in state_machine.get_children():
		if !child is HUDState:
			continue
		child.hide_ui()


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if null_hud_state == null:
		issues.append("null_hud_state must not be empty")
	if riding_hud_state == null:
		issues.append("riding_hud_state must not be empty")
	if state_machine == null:
		issues.append("state_machine must not be empty")
	return issues
