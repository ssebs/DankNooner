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
