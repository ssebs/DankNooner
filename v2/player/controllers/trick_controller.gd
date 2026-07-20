@tool
class_name TrickController extends Node

signal trick_started(trick_type: Trick)
signal trick_ended(trick_type: Trick)

enum Trick {
	NONE,
	WHEELIE_SITTING,
	WHEELIE_MOD,
	STOPPIE,
	BACKFLIP,
	FRONTFLIP,
	THREESIXTY,
	HEEL_CLICKER,
	HIGH_CHAIR,
	TWO_LEFT_FEET,
	DRIFT,
}
@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var gearing_controller: GearingController
@export var movement_controller: MovementController

const TRICK_CAM_THRESHOLD: float = -0.5
const TWO_LEFT_FEET_SPEED_THRESHOLD: float = 20
## Pitch (degrees) past which the bike is considered in a wheelie / stoppie.
## Shared by movement_controller for in_wheelie / in_stoppie checks.
const WHEELIE_PITCH_THRESHOLD_DEG: float = 10.0
const STOPPIE_PITCH_THRESHOLD_DEG: float = -10.0
## Boost segments earned per second of trick, before the combo multiplier. At x1 that's ~2s
## of wheelie per segment, ~6s for a full meter — short enough that a casual wheelie earns
## something usable. Consts, not @exports: this runs inside the rollback tick and must be
## byte-identical on every peer or predictions diverge from the server.
const BOOST_PER_SEC: float = 0.2
## Dropping every trick starts this grace window instead of breaking the combo outright,
## so wheelie -> stoppie -> wheelie chains keep their multiplier.
const COMBO_GRACE_SECS: float = 1.5
## Seconds of unbroken trick time to reach each multiplier above x1, ascending.
const COMBO_MULT_THRESHOLDS: Array[float] = [10.0, 30.0]

var current_trick: Trick = Trick.NONE
var _last_trick: Trick = Trick.NONE
var _flip_emitted: bool = false  # prevent re-emitting the same flip while still airborne
var _trick_timer: float = 0.0


func _ready():
	if Engine.is_editor_hint():
		return


## Called from MovementController._rollback_tick()
func on_movement_rollback_tick(delta: float):
	if player_entity.is_crashed:
		return

	current_trick = _detect_current_trick(delta)
	if current_trick != _last_trick:
		if _last_trick != Trick.NONE:
			trick_ended.emit(_last_trick)
		if current_trick != Trick.NONE:
			trick_started.emit(current_trick)
		_last_trick = current_trick

	_accrue_combo(delta)


## Accrue combo time + boost for the tick. Lives here (rollback) rather than in TrickManager
## because these are netfox state properties — RollbackSynchronizer re-applies them from
## history every tick, so a manager writing them in _process() would be overwritten before
## anything accumulated. TrickManager banks the SCORE when the combo ends, off these values.
func _accrue_combo(delta: float):
	var pe := player_entity

	if current_trick != Trick.NONE:
		pe.combo_time += delta
		pe.combo_grace = COMBO_GRACE_SECS
		# Track what this combo contributed (post-cap, so a full meter doesn't inflate the
		# claim) — a crash voids exactly this much and nothing that was banked earlier.
		var before: float = pe.boost_amount
		pe.boost_amount = minf(
			pe.boost_amount + BOOST_PER_SEC * pe.combo_multiplier * delta,
			MovementController.BOOST_SEGMENTS
		)
		pe.combo_boost_earned += pe.boost_amount - before
	elif pe.combo_time > 0.0:
		pe.combo_grace -= delta
		if pe.combo_grace <= 0.0:
			pe.combo_time = 0.0
			pe.combo_grace = 0.0
			# Survived the grace window — this combo's boost is banked for good now.
			pe.combo_boost_earned = 0.0

	var mult := 1
	for threshold in COMBO_MULT_THRESHOLDS:
		if pe.combo_time >= threshold:
			mult += 1
	pe.combo_multiplier = mult


func _detect_current_trick(delta: float) -> Trick:
	if !movement_controller._is_on_floor:
		return _detect_air_trick()

	# Reset flip tracking on landing
	_flip_emitted = false

	if movement_controller.is_drifting:
		return Trick.DRIFT

	if movement_controller.pitch_angle > deg_to_rad(WHEELIE_PITCH_THRESHOLD_DEG):
		if input_controller.nfx_trick_held:
			# HIGH_CHAIR latches: once entered (via cam-down flick), stays held while
			# RB is held + still in a wheelie. Releasing RB or dropping the wheelie exits.
			if current_trick == Trick.HIGH_CHAIR:
				return Trick.HIGH_CHAIR
			if input_controller.nfx_cam_y > -TRICK_CAM_THRESHOLD:
				return Trick.HIGH_CHAIR
			if input_controller.nfx_cam_y < TRICK_CAM_THRESHOLD:
				return Trick.HEEL_CLICKER
			return Trick.WHEELIE_MOD
		return Trick.WHEELIE_SITTING

	if movement_controller.pitch_angle < deg_to_rad(STOPPIE_PITCH_THRESHOLD_DEG):
		return Trick.STOPPIE

	if input_controller.nfx_trick_held:
		if (
			input_controller.nfx_cam_x < TRICK_CAM_THRESHOLD
			and movement_controller.speed > TWO_LEFT_FEET_SPEED_THRESHOLD
		):
			return Trick.TWO_LEFT_FEET

	if _last_trick == Trick.TWO_LEFT_FEET:
		if _trick_timer <= 3:  # HACK - duration of the animation
			_trick_timer += delta
			return Trick.TWO_LEFT_FEET
		_trick_timer = 0

	return Trick.NONE


func _detect_air_trick() -> Trick:
	# HIGH_CHAIR (air entry: RB + cam up) — latches while RB held + airborne.
	# -TRICK_CAM_THRESHOLD == 0.5 (cam stick up).
	if input_controller.nfx_trick_held:
		if current_trick == Trick.HIGH_CHAIR:
			return Trick.HIGH_CHAIR

		if input_controller.nfx_cam_y > -TRICK_CAM_THRESHOLD:
			return Trick.HIGH_CHAIR

		# Heel clicker — held while airborne with trick btn + cam stick down
		if input_controller.nfx_cam_y < TRICK_CAM_THRESHOLD:
			return Trick.HEEL_CLICKER

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
	# Drain any active trick so listeners (HUD balance bar, etc.) clean up
	if _last_trick != Trick.NONE:
		trick_ended.emit(_last_trick)
	current_trick = Trick.NONE
	_last_trick = Trick.NONE
	_flip_emitted = false
	player_entity.combo_time = 0.0
	player_entity.combo_grace = 0.0
	player_entity.combo_multiplier = 1


func is_in_wheelie() -> bool:
	return current_trick in [Trick.WHEELIE_SITTING, Trick.WHEELIE_MOD]


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
		Trick.HEEL_CLICKER:
			return "HEEL_CLICKER"
		Trick.HIGH_CHAIR:
			return "HIGH_CHAIR"
		Trick.TWO_LEFT_FEET:
			return "TWO_LEFT_FEET"
		Trick.DRIFT:
			return "DRIFT"
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
		"HEEL_CLICKER":
			return Trick.HEEL_CLICKER
		"HIGH_CHAIR":
			return Trick.HIGH_CHAIR
		"TWO_LEFT_FEET":
			return Trick.TWO_LEFT_FEET
		"DRIFT":
			return Trick.DRIFT
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
