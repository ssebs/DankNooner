@tool
class_name TrickController extends Node

signal trick_started(trick_type: Trick)
signal trick_ended(trick_type: Trick)

enum Trick { NONE, WHEELIE_SITTING, WHEELIE_MOD, STOPPIE, BACKFLIP, FRONTFLIP, THREESIXTY }

@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var gearing_controller: GearingController
@export var movement_controller: MovementController

var _current_trick: Trick = Trick.NONE
var _last_trick: Trick = Trick.NONE
var _flip_emitted: bool = false  # prevent re-emitting the same flip while still airborne


func _ready():
	if Engine.is_editor_hint():
		return


## Called from MovementController._rollback_tick()
func on_movement_rollback_tick(_delta: float):
	_current_trick = _detect_current_trick()
	if _current_trick != _last_trick:
		if _last_trick != Trick.NONE:
			trick_ended.emit(_last_trick)
		if _current_trick != Trick.NONE:
			trick_started.emit(_current_trick)
		_last_trick = _current_trick


func _detect_current_trick() -> Trick:
	if !movement_controller._is_on_floor:
		return _detect_air_trick()

	# Reset flip tracking on landing
	_flip_emitted = false

	if movement_controller.pitch_angle > deg_to_rad(10):
		if input_controller.nfx_trick_held:
			return Trick.WHEELIE_MOD
		return Trick.WHEELIE_SITTING

	if movement_controller.pitch_angle < deg_to_rad(-10):
		return Trick.STOPPIE
	return Trick.NONE


func _detect_air_trick() -> Trick:
	if movement_controller.air_pitch_total < (TAU * 0.9):
		return Trick.NONE

	# Full flip completed — determine direction from pitch_angle sign
	if _flip_emitted:
		return Trick.NONE

	_flip_emitted = true
	if movement_controller.pitch_angle > 0:
		return Trick.BACKFLIP

	return Trick.FRONTFLIP


## Called from player_entity.gd's do_respawn
func do_reset():
	_current_trick = Trick.NONE
	_last_trick = Trick.NONE
	_flip_emitted = false


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
		Trick.BACKFLIP:
			return "BACKFLIP"
		Trick.FRONTFLIP:
			return "FRONTFLIP"
		Trick.THREESIXTY:
			return "THREESIXTY"
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
		"BACKFLIP":
			return Trick.BACKFLIP
		"FRONTFLIP":
			return Trick.FRONTFLIP
		"THREESIXTY":
			return Trick.THREESIXTY
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
