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
	KICKFLIP,
	SPREAD_EAGLE,
	SUPERMAN,
	DRIFT,
	BURNOUT,
}
@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var gearing_controller: GearingController
@export var movement_controller: MovementController
@export var boost_controller: BoostController

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
## Keep these in the same ballpark as the meter fill time (BOOST_PER_SEC) — the gauge is the
## only feedback the player can actually see, so a multiplier that lags far behind it reads
## as broken. At 0.2/sec: x2 lands around the first full segment, x3 well after the meter
## caps (where it still matters, since score = duration x rate x peak multiplier).
const COMBO_MULT_THRESHOLDS: Array[float] = [5.0, 15.0]
## Boost segments banked per completed air rotation (each flip) and per landed air trick, before
## the combo multiplier. A chunk, not a full meter — a big combo multiplier is what fills a bar.
## Consts (rollback): must be byte-identical on every peer.
const BOOST_PER_FLIP: float = 0.5
const BOOST_PER_AIR_TRICK: float = 0.5

## Seconds of unbroken trick time on the current combo, 0 when not comboing. Accrued in this
## controller's rollback tick — NOT from a manager's _process(): netfox's RollbackSynchronizer
## re-applies every state property from history on each tick, so writes made outside the
## rollback window are silently overwritten before they accumulate.
var combo_time: float = 0.0
## Remaining grace before dropping every trick actually breaks the combo.
var combo_grace: float = 0.0
## How much of the CURRENT boost meter was earned by the combo still in progress. A crash
## voids only this much, so boost banked by earlier completed combos survives. Cleared when
## a combo ends cleanly (that boost is now permanent) and drawn down alongside boost_amount
## when spending, so spending the pool doesn't leave a stale over-large claim behind.
var combo_boost_earned: float = 0.0
## Combo multiplier (1+), derived from combo_time each rollback tick.
var combo_multiplier: int = 1

var current_trick: Trick = Trick.NONE
var _last_trick: Trick = Trick.NONE
var _flip_emitted: bool = false  # prevent re-emitting the same flip while still airborne
var _trick_timer: float = 0.0
## Full air rotations already paid out this airtime — synced so a resim doesn't double-award.
var _air_flips_awarded: int = 0


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
			# Landing an air trick banks a chunk (void-on-crash means you must land it clean).
			if not movement_controller._is_on_floor and is_air_trick(current_trick):
				_award_trick_boost(BOOST_PER_AIR_TRICK)
		_last_trick = current_trick

	_award_flip_boost()
	_accrue_combo(delta)


## Bank a chunk per full air rotation as it completes. air_pitch_total resets to 0 on takeoff /
## landing, so the paid-out counter re-arms on the ground.
func _award_flip_boost():
	if not movement_controller._is_on_floor:
		var completed := int(movement_controller.air_pitch_total / TAU)
		if completed > _air_flips_awarded:
			_award_trick_boost(BOOST_PER_FLIP * (completed - _air_flips_awarded))
			_air_flips_awarded = completed
	else:
		_air_flips_awarded = 0


## Add a lump of trick boost, scaled by the current combo multiplier. Tracked in combo_boost_earned
## like the per-second accrual, so a crash before the combo banks (incl. a mid-trick landing) voids
## it — land it to keep it.
func _award_trick_boost(base: float):
	var before: float = boost_controller.boost_amount
	boost_controller.boost_amount = minf(
		boost_controller.boost_amount + base * combo_multiplier, BoostController.BOOST_SEGMENTS
	)
	combo_boost_earned += boost_controller.boost_amount - before
	combo_grace = COMBO_GRACE_SECS  # keep the combo alive so chained tricks build the multiplier


## Accrue combo time + boost for the tick. Lives here (rollback) rather than in TrickManager
## because these are netfox state properties — RollbackSynchronizer re-applies them from
## history every tick, so a manager writing them in _process() would be overwritten before
## anything accumulated. TrickManager banks the SCORE when the combo ends, off these values.
func _accrue_combo(delta: float):
	if current_trick != Trick.NONE:
		combo_time += delta
		combo_grace = COMBO_GRACE_SECS
		# Track what this combo contributed (post-cap, so a full meter doesn't inflate the
		# claim) — a crash voids exactly this much and nothing that was banked earlier.
		var before: float = boost_controller.boost_amount
		boost_controller.boost_amount = minf(
			boost_controller.boost_amount + BOOST_PER_SEC * combo_multiplier * delta,
			BoostController.BOOST_SEGMENTS
		)
		combo_boost_earned += boost_controller.boost_amount - before
	elif combo_time > 0.0:
		combo_grace -= delta
		if combo_grace <= 0.0:
			combo_time = 0.0
			combo_grace = 0.0
			# Survived the grace window — this combo's boost is banked for good now.
			combo_boost_earned = 0.0

	var mult := 1
	for threshold in COMBO_MULT_THRESHOLDS:
		if combo_time >= threshold:
			mult += 1
	combo_multiplier = mult


func _detect_current_trick(delta: float) -> Trick:
	if !movement_controller._is_on_floor:
		return _detect_air_trick()

	# Reset flip tracking on landing
	_flip_emitted = false

	if movement_controller.is_drifting:
		# Drifting at a near-standstill is a burnout (rear spinning in place); moving is a drift.
		if movement_controller.speed < MovementController.DRIFT_MIN_SPEED:
			return Trick.BURNOUT
		return Trick.DRIFT

	if movement_controller.pitch_angle > deg_to_rad(WHEELIE_PITCH_THRESHOLD_DEG):
		# In the balance point the right stick pops tweaks on top of the wheelie; neutral stick
		# (or a wheelie below the window) stays the plain WHEELIE_SITTING — physics unchanged.
		if movement_controller.in_balance_point:
			# Held while the stick is pushed; neutral returns to the plain wheelie (no latch).
			if input_controller.nfx_cam_y > -TRICK_CAM_THRESHOLD:
				return Trick.HIGH_CHAIR
			if input_controller.nfx_cam_y < TRICK_CAM_THRESHOLD:
				return Trick.HEEL_CLICKER
		return Trick.WHEELIE_SITTING

	# Only a braking-held stoppie scores — a nose-down landing or coast isn't a stoppie.
	if movement_controller.is_stoppie:
		return Trick.STOPPIE

	# RB + stick direction = flat-ground tricks. Up = kickflip, left = two left feet.
	if input_controller.nfx_trick_held:
		if input_controller.nfx_cam_y > -TRICK_CAM_THRESHOLD:
			return Trick.KICKFLIP
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
	# Airborne is itself the gate — the right stick drives the tweaks, no RB. Held while the
	# stick is pushed (no latch). -TRICK_CAM_THRESHOLD == 0.5 (cam stick up).
	if input_controller.nfx_cam_y > -TRICK_CAM_THRESHOLD:
		return Trick.HIGH_CHAIR

	# Heel clicker — held while airborne with cam stick down
	if input_controller.nfx_cam_y < TRICK_CAM_THRESHOLD:
		return Trick.HEEL_CLICKER

	# Left = spread eagle, right = superman (up/down taken above).
	if input_controller.nfx_cam_x < TRICK_CAM_THRESHOLD:
		return Trick.SPREAD_EAGLE
	if input_controller.nfx_cam_x > -TRICK_CAM_THRESHOLD:
		return Trick.SUPERMAN

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
	_air_flips_awarded = 0
	combo_time = 0.0
	combo_grace = 0.0
	combo_boost_earned = 0.0
	combo_multiplier = 1


func is_in_wheelie() -> bool:
	return current_trick in [Trick.WHEELIE_SITTING, Trick.WHEELIE_MOD]


## Tricks that must be finished before touching down — landing mid-trick crashes (see
## CrashController._detect_air_trick_landing). Kickflip / two left feet are ground tricks.
static func is_air_trick(trick: Trick) -> bool:
	return trick in [Trick.HEEL_CLICKER, Trick.SPREAD_EAGLE, Trick.SUPERMAN]


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
		Trick.KICKFLIP:
			return "KICKFLIP"
		Trick.SPREAD_EAGLE:
			return "SPREAD_EAGLE"
		Trick.SUPERMAN:
			return "SUPERMAN"
		Trick.DRIFT:
			return "DRIFT"
		Trick.BURNOUT:
			return "BURNOUT"
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
		"KICKFLIP":
			return Trick.KICKFLIP
		"SPREAD_EAGLE":
			return Trick.SPREAD_EAGLE
		"SUPERMAN":
			return Trick.SUPERMAN
		"DRIFT":
			return Trick.DRIFT
		"BURNOUT":
			return Trick.BURNOUT
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
	if boost_controller == null:
		issues.append("boost_controller must not be empty")
	return issues
