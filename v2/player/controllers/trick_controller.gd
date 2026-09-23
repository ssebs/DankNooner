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
	T_POSE,
	KNEE_KNOCKER,
}
enum Dir { UP, DOWN, LEFT, RIGHT }
## TAP / DOUBLE_TAP latch their trick for TAP_TRICK_DURATION; HOLD / DOUBLE_TAP_HOLD keep it active
## while the stick stays pushed. Any trick works in any slot.
enum Gesture { TAP, DOUBLE_TAP, HOLD, DOUBLE_TAP_HOLD }
## Which BINDINGS table the right stick reads. NONE = stick tricks gated off.
enum TrickState { NONE, GROUND, WHEELIE, AIR }
@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var gearing_controller: GearingController
@export var movement_controller: MovementController
@export var boost_controller: BoostController

const TRICK_CAM_THRESHOLD: float = -0.5
const TWO_LEFT_FEET_SPEED_THRESHOLD: float = 20
## Airborne time before any right-stick air trick can register. A bump or curb mid-ground-trick isn't
## a real jump: without this, a held ground trick flicks to an air trick on the hop and crashes on
## touchdown (landed-mid-air-trick).
## Real jumps clear it easily. Const (rollback): byte-identical on every peer.
const AIR_TRICK_MIN_AIRTIME: float = 0.25
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
## A cam flick released before this is a tap; holding longer is a HOLD gesture. Const (rollback):
## byte-identical on every peer. Raising it makes the tap more forgiving but delays holds.
const TAP_TRICK_MAX_SECS: float = 0.25
## A second press in the same direction within this window (from the first release) is a double
## tap, or a double-tap-hold if it's held. A single tap fires once the window expires, so this is
## also single-tap latency.
const DOUBLE_TAP_WINDOW: float = 0.25
## Seconds a tap trick stays the active trick (the kickflip anim length; hold anims stay posed for
## it). Latched because a tap has no held phase to keep it alive, unlike the stick-held tricks.
const TAP_TRICK_DURATION: float = 1.0
const NO_DIR: int = -1
## Per-trick score, in "seconds at TrickManager.points_per_second". Held tricks earn their value per
## second while active; one-time tricks bank it once, when they start. Consts (rollback).
const HELD_TRICK_SCORE: Dictionary = {
	Trick.WHEELIE_SITTING: 1.0,
	Trick.WHEELIE_MOD: 1.0,
	Trick.STOPPIE: 1.0,
	Trick.DRIFT: 1.0,
	Trick.BURNOUT: 0.5,
	Trick.HIGH_CHAIR: 1.5,
	Trick.KNEE_KNOCKER: 1.5,
	Trick.T_POSE: 1.5,
	Trick.TWO_LEFT_FEET: 1.5,
	Trick.SPREAD_EAGLE: 2.0,
	Trick.SUPERMAN: 2.0,
}
const ONE_TIME_TRICK_SCORE: Dictionary = {
	Trick.HEEL_CLICKER: 1.5,
	Trick.KICKFLIP: 3.0,
	Trick.BACKFLIP: 5.0,
	Trick.FRONTFLIP: 5.0,
	Trick.THREESIXTY: 5.0,
}
## Right-stick control scheme: state -> gesture -> trick per Dir (UP, DOWN, LEFT, RIGHT). Guideline:
## shared tricks keep one tap / double-tap slot across states (double tap = harder trick); HOLD is
## for state-specific tricks. Const (rollback): byte-identical on every peer.
const BINDINGS: Dictionary = {
	TrickState.WHEELIE:
	{
		Gesture.TAP: [Trick.NONE, Trick.HEEL_CLICKER, Trick.NONE, Trick.NONE],
		Gesture.DOUBLE_TAP: [Trick.NONE, Trick.NONE, Trick.KICKFLIP, Trick.NONE],
		Gesture.HOLD: [Trick.HIGH_CHAIR, Trick.NONE, Trick.KNEE_KNOCKER, Trick.T_POSE],
		Gesture.DOUBLE_TAP_HOLD: [Trick.NONE, Trick.NONE, Trick.NONE, Trick.NONE],
	},
	TrickState.GROUND:
	{
		Gesture.TAP: [Trick.NONE, Trick.HEEL_CLICKER, Trick.NONE, Trick.NONE],
		Gesture.DOUBLE_TAP: [Trick.NONE, Trick.NONE, Trick.KICKFLIP, Trick.NONE],
		Gesture.HOLD: [Trick.HIGH_CHAIR, Trick.TWO_LEFT_FEET, Trick.KNEE_KNOCKER, Trick.T_POSE],
		Gesture.DOUBLE_TAP_HOLD: [Trick.NONE, Trick.NONE, Trick.NONE, Trick.NONE],
	},
	TrickState.AIR:
	{
		Gesture.TAP: [Trick.NONE, Trick.HEEL_CLICKER, Trick.NONE, Trick.NONE],
		Gesture.DOUBLE_TAP: [Trick.NONE, Trick.NONE, Trick.KICKFLIP, Trick.NONE],
		Gesture.HOLD: [Trick.HIGH_CHAIR, Trick.NONE, Trick.KNEE_KNOCKER, Trick.T_POSE],
		Gesture.DOUBLE_TAP_HOLD: [Trick.NONE, Trick.NONE, Trick.SPREAD_EAGLE, Trick.SUPERMAN],
	},
}

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
## Score the combo in progress has earned (see HELD_TRICK_SCORE / ONE_TIME_TRICK_SCORE).
## TrickManager banks it when the combo ends.
var combo_score: float = 0.0

var current_trick: Trick = Trick.NONE
var _last_trick: Trick = Trick.NONE
var _flip_emitted: bool = false  # prevent re-emitting the same flip while still airborne
var _trick_timer: float = 0.0
## Full air rotations already paid out this airtime — synced so a resim doesn't double-award.
var _air_flips_awarded: int = 0
## Gesture state (all synced: read/written in the rollback tick and gates tricks, so combo_time,
## which is synced, stays consistent on resim). Direction the stick is pushed (NO_DIR = neutral)
## and for how long, whether this press is the second of a double tap; plus a released tap waiting
## out DOUBLE_TAP_WINDOW.
var _hold_dir: int = NO_DIR
var _hold_time: float = 0.0
var _press_double: bool = false
var _tap_dir: int = NO_DIR
var _tap_age: float = 0.0
## Latched tap trick and its remaining seconds (synced). Timer >0 = _tap_trick is the active trick.
var _tap_trick: Trick = Trick.NONE
var _tap_trick_timer: float = 0.0


func _ready():
	if Engine.is_editor_hint():
		return


## Called from MovementController._rollback_tick()
func on_movement_rollback_tick(delta: float):
	if player_entity.is_crashed:
		return

	_update_gestures(delta)
	current_trick = _detect_current_trick(delta)
	if current_trick != _last_trick:
		if _last_trick != Trick.NONE:
			trick_ended.emit(_last_trick)
		if current_trick != Trick.NONE:
			trick_started.emit(current_trick)
			combo_score += ONE_TIME_TRICK_SCORE.get(current_trick, 0.0)
			# Landing an air trick banks a chunk (void-on-crash means you must land it clean).
			if not movement_controller._is_on_floor and is_air_trick(current_trick):
				_award_trick_boost(BOOST_PER_AIR_TRICK)
		_last_trick = current_trick

	_award_flip_boost()
	_accrue_combo(delta)


## Turn the right stick into TAP / DOUBLE_TAP gestures and latch their BINDINGS trick. The held
## gestures are read live by _held_trick(). Lives in the rollback tick — not a local input poll like
## the respawn tap/hold — so the latch it drives stays byte-identical on every peer.
func _update_gestures(delta: float):
	if _tap_trick_timer > 0.0:
		_tap_trick_timer -= delta

	var dir := _stick_dir()
	if dir != _hold_dir:
		# Released (or swung to another direction) — a short press is a tap.
		if _hold_dir != NO_DIR and _hold_time < TAP_TRICK_MAX_SECS:
			if _press_double:
				_latch_gesture(Gesture.DOUBLE_TAP, _hold_dir)
			else:
				# A pending tap in another direction fires now rather than being dropped.
				if _tap_dir != NO_DIR:
					_latch_gesture(Gesture.TAP, _tap_dir)
				_tap_dir = _hold_dir
				_tap_age = 0.0
		# A press toward a pending tap is its second press: it resolves as DOUBLE_TAP on a quick
		# release or DOUBLE_TAP_HOLD if held, so the pending single tap is consumed.
		_press_double = dir != NO_DIR and dir == _tap_dir
		if _press_double:
			_tap_dir = NO_DIR
		_hold_dir = dir
		_hold_time = 0.0
	if dir != NO_DIR:
		_hold_time += delta

	if _tap_dir != NO_DIR:
		_tap_age += delta
		if _tap_age >= DOUBLE_TAP_WINDOW:
			_latch_gesture(Gesture.TAP, _tap_dir)
			_tap_dir = NO_DIR


func _latch_gesture(gesture: Gesture, dir: int):
	var trick := _bound_trick(gesture, dir)
	# Skip while a tap trick is already latched.
	if trick != Trick.NONE and _tap_trick_timer <= 0.0:
		_tap_trick = trick
		_tap_trick_timer = TAP_TRICK_DURATION


## BINDINGS HOLD / DOUBLE_TAP_HOLD trick for the stick held past the tap window, else NONE.
func _held_trick() -> Trick:
	if _hold_dir == NO_DIR or _hold_time < TAP_TRICK_MAX_SECS:
		return Trick.NONE
	var gesture := Gesture.DOUBLE_TAP_HOLD if _press_double else Gesture.HOLD
	return _bound_trick(gesture, _hold_dir)


func _bound_trick(gesture: Gesture, dir: int) -> Trick:
	var state := _trick_state()
	if state == TrickState.NONE:
		return Trick.NONE
	var trick: Trick = BINDINGS[state][gesture][dir]
	if trick == Trick.TWO_LEFT_FEET and movement_controller.speed <= TWO_LEFT_FEET_SPEED_THRESHOLD:
		return Trick.NONE
	return trick


## Which BINDINGS table applies right now, or NONE when stick tricks are gated off.
func _trick_state() -> TrickState:
	if not movement_controller._is_on_floor:
		# A brief hop (curb, bump) isn't a real jump — a ground trick held over a bump would
		# otherwise flick to an air trick and crash on touchdown (landed-mid-air-trick).
		if movement_controller._air_time < AIR_TRICK_MIN_AIRTIME:
			return TrickState.NONE
		return TrickState.AIR
	if movement_controller.pitch_angle > deg_to_rad(WHEELIE_PITCH_THRESHOLD_DEG):
		# Tweaks only in the balance point; a wheelie below the window stays the plain wheelie.
		return TrickState.WHEELIE if movement_controller.in_balance_point else TrickState.NONE
	# On the ground the trick button must be held, so the stick still drives the camera otherwise.
	return TrickState.GROUND if input_controller.nfx_trick_held else TrickState.NONE


## Dominant right-stick direction past the trick threshold, or NO_DIR.
func _stick_dir() -> int:
	var x := input_controller.nfx_cam_x
	var y := input_controller.nfx_cam_y
	if maxf(absf(x), absf(y)) < -TRICK_CAM_THRESHOLD:
		return NO_DIR
	if absf(y) >= absf(x):
		return Dir.UP if y > 0.0 else Dir.DOWN
	return Dir.RIGHT if x > 0.0 else Dir.LEFT


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
		combo_score += HELD_TRICK_SCORE.get(current_trick, 0.0) * delta
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
			combo_score = 0.0
			# Survived the grace window — this combo's boost is banked for good now.
			combo_boost_earned = 0.0

	var mult := 1
	for threshold in COMBO_MULT_THRESHOLDS:
		if combo_time >= threshold:
			mult += 1
	combo_multiplier = mult


func _detect_current_trick(delta: float) -> Trick:
	# Tap trick latch overrides everything (ground or air) while it's running.
	if _tap_trick_timer > 0.0:
		return _tap_trick

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
		# Neutral stick stays the plain WHEELIE_SITTING — physics unchanged.
		var wheelie_held := _held_trick()
		if wheelie_held != Trick.NONE:
			return wheelie_held
		return Trick.WHEELIE_SITTING

	# Only a braking-held stoppie scores — a nose-down landing or coast isn't a stoppie.
	if movement_controller.is_stoppie:
		return Trick.STOPPIE

	var held := _held_trick()
	if held != Trick.NONE:
		return held

	if _last_trick == Trick.TWO_LEFT_FEET:
		if _trick_timer <= 3:  # HACK - duration of the animation
			_trick_timer += delta
			return Trick.TWO_LEFT_FEET
		_trick_timer = 0

	return Trick.NONE


func _detect_air_trick() -> Trick:
	# Airborne is itself the gate — no RB. _trick_state() applies the min-airtime gate; flips need
	# far more airtime than that, so it doesn't affect them.
	var held := _held_trick()
	if held != Trick.NONE:
		return held

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
	_hold_dir = NO_DIR
	_hold_time = 0.0
	_press_double = false
	_tap_dir = NO_DIR
	_tap_age = 0.0
	_tap_trick = Trick.NONE
	_tap_trick_timer = 0.0
	combo_time = 0.0
	combo_grace = 0.0
	combo_boost_earned = 0.0
	combo_multiplier = 1
	combo_score = 0.0


func is_in_wheelie() -> bool:
	return current_trick in [Trick.WHEELIE_SITTING, Trick.WHEELIE_MOD]


## Tricks that must be finished before touching down — landing mid-trick crashes (see
## CrashController._detect_air_trick_landing). That only checks the landing tick, so the ground
## versions of kickflip / T-pose / knee knocker stay safe.
static func is_air_trick(trick: Trick) -> bool:
	return trick in [
		Trick.HEEL_CLICKER,
		Trick.SPREAD_EAGLE,
		Trick.SUPERMAN,
		Trick.KICKFLIP,
		Trick.T_POSE,
		Trick.KNEE_KNOCKER,
	]


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
		Trick.T_POSE:
			return "T_POSE"
		Trick.KNEE_KNOCKER:
			return "KNEE_KNOCKER"
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
		"T_POSE":
			return Trick.T_POSE
		"KNEE_KNOCKER":
			return Trick.KNEE_KNOCKER
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
