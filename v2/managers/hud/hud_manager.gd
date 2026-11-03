@tool
class_name HUDManager extends BaseManager

@export var state_machine: StateMachine

@export var null_hud_state: HUDState
@export var riding_hud_state: RidingHUDState
@export var fuel_up_hud_state: FuelUpHUDState
@export var garage_hud_state: GarageHUDState

var local_player: PlayerEntity

var _dbg_hud_hidden: bool = false

func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	Console.add_command("dbg_hud", _toggle_hud_debug, [], 0, "Toggle hiding the HUD, for recording clips")

func go_to_riding_hud():
	state_machine.request_state_change(riding_hud_state)


func go_to_fuel_up_hud(minigame: FuelUpMinigame):
	fuel_up_hud_state.minigame = minigame
	state_machine.request_state_change(fuel_up_hud_state)


func go_to_garage_hud(activity: GarageActivity):
	garage_hud_state.activity = activity
	state_machine.request_state_change(garage_hud_state)


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


## Alpha, not visible, so state changes and unpause (which all show()) can't undo it.
## Covers every CanvasItem under a HUD state, e.g. RidingHUDState's netfox debug label.
func _toggle_hud_debug() -> void:
	_dbg_hud_hidden = !_dbg_hud_hidden
	for hud_state in state_machine.get_children():
		for child in hud_state.get_children():
			if child is CanvasItem:
				child.modulate.a = 0.0 if _dbg_hud_hidden else 1.0
	Console.print_line("dbg_hud: %s" % ("hidden" if _dbg_hud_hidden else "shown"))


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if null_hud_state == null:
		issues.append("null_hud_state must not be empty")
	if riding_hud_state == null:
		issues.append("riding_hud_state must not be empty")
	if fuel_up_hud_state == null:
		issues.append("fuel_up_hud_state must not be empty")
	if garage_hud_state == null:
		issues.append("garage_hud_state must not be empty")
	if state_machine == null:
		issues.append("state_machine must not be empty")
	return issues
