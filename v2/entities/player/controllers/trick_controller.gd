@tool
class_name TrickController extends Node

signal trick_started(trick_type: Trick)
signal trick_ended(trick_type: Trick)

enum Trick { NONE, WHEELIE_SITTING, WHEELIE_MOD, STOPPIE }

@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var gearing_controller: GearingController
@export var movement_controller: MovementController

const CLUTCH_KICK_WINDOW: float = 0.4  # seconds after clutch dump to allow wheelie pop

var current_trick: Trick = Trick.NONE
var _last_trick: Trick = Trick.NONE
var _clutch_kick_window: float = 0.0
var _prev_clutch_held: bool = false


func _ready():
	if Engine.is_editor_hint():
		return


## Called from MovementController._rollback_tick()
func on_movement_rollback_tick(_delta: float):
	current_trick = _detect_current_trick()


func _detect_current_trick() -> Trick:
	if movement_controller.pitch_angle > deg_to_rad(15):
		if input_controller.trick_held:
			return Trick.WHEELIE_MOD
		return Trick.WHEELIE_SITTING

	if movement_controller.pitch_angle < deg_to_rad(-10):
		return Trick.STOPPIE
	return Trick.NONE


## Called from player_entity.gd's do_respawn
func do_reset():
	current_trick = Trick.NONE
	_last_trick = Trick.NONE
	_clutch_kick_window = 0.0
	_prev_clutch_held = false
	movement_controller.pitch_angle = 0


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if player_entity == null:
		issues.append("player_entity must not be empty")
	if input_controller == null:
		issues.append("input_controller must not be empty")
	if gearing_controller == null:
		issues.append("gearing_controller must not be empty")
	if movement_controller == null:
		issues.append("movement_controller must not be empty")
	return issues
