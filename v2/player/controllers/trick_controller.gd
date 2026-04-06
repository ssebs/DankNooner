@tool
class_name TrickController extends Node

signal trick_started(trick_type: Trick)
signal trick_ended(trick_type: Trick)

enum Trick { NONE, WHEELIE_SITTING, WHEELIE_MOD, STOPPIE }

@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var gearing_controller: GearingController
@export var movement_controller: MovementController

var _current_trick: Trick = Trick.NONE
var _last_trick: Trick = Trick.NONE


func _ready():
	if Engine.is_editor_hint():
		return


## Called from MovementController._rollback_tick()
func on_movement_rollback_tick(_delta: float):
	_current_trick = _detect_current_trick()
	if _current_trick == Trick.NONE:
		trick_ended.emit(_last_trick)
	elif _current_trick != _last_trick:
		_last_trick = _current_trick
		trick_ended.emit(_last_trick)
		trick_started.emit(_current_trick)
		do_reset()


func _detect_current_trick() -> Trick:
	# Air tricks don't count as wheelies/stoppies
	if not movement_controller._is_on_floor:
		return Trick.NONE

	if movement_controller.pitch_angle > deg_to_rad(15):
		if input_controller.nfx_trick_held:
			return Trick.WHEELIE_MOD
		return Trick.WHEELIE_SITTING

	if movement_controller.pitch_angle < deg_to_rad(-10):
		return Trick.STOPPIE
	return Trick.NONE


## Called from player_entity.gd's do_respawn
func do_reset():
	_current_trick = Trick.NONE
	_last_trick = Trick.NONE


static func trick_to_str(trick: Trick) -> String:
	match trick:
		Trick.NONE:
			return "NONE"
		Trick.WHEELIE_SITTING:
			return "WHEELIE_SITTING"
		Trick.WHEELIE_MOD:
			return "WHEELIE_MOD"
		Trick.STOPPIE:
			return "STOPPIE"
	return "NONE"


static func str_to_trick(s: String) -> Trick:
	match s:
		"NONE":
			return Trick.NONE
		"WHEELIE_SITTING":
			return Trick.WHEELIE_SITTING
		"WHEELIE_MOD":
			return Trick.WHEELIE_MOD
		"STOPPIE":
			return Trick.STOPPIE
	return Trick.NONE


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
