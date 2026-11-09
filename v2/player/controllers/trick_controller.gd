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
	BUNNY_HOP,
	DRIFT_WHEELIE,
	FIFTY_FIFTY,
	FIVE_O,
	NOSEGRIND,
	CROOKED,
	FEEBLE,
	SALAD,
	BOARDSLIDE,
	LIPSLIDE,
	NOSESLIDE,
	TAILSLIDE,
	SMITH,
	SUSKI,
	OVERCROOK,
	NOSEBLUNT,
	BLUNTSLIDE,
	WILLY,
	OVER_WILLY,
}
enum Dir {UP, DOWN, LEFT, RIGHT}
## TAP / DOUBLE_TAP latch their trick for TAP_TRICK_DURATION; HOLD / DOUBLE_TAP_HOLD keep it active
## while the stick stays pushed. Any trick works in any slot.
enum Gesture {TAP, DOUBLE_TAP, HOLD, DOUBLE_TAP_HOLD}
## Which BINDINGS table the right stick reads. NONE = stick tricks gated off.
enum TrickState {NONE, GROUND, WHEELIE, AIR, GRIND}
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
## A wheelie ends once pitch stays under WHEELIE_EXIT_PITCH_DEG for WHEELIE_EXIT_DELAY seconds (same
## idea as AUTO_DOWNSHIFT_DELAY). Below the entry threshold, so a nose bobbing across it — power
## fading in a tall gear — stays one wheelie instead of restarting the trick every crossing.
const WHEELIE_EXIT_PITCH_DEG: float = 5.0
const WHEELIE_EXIT_DELAY: float = 0.2
## Near miss (passing traffic close, see NPCTrafficState) score by the HUD's speed: nothing under
## NEAR_MISS_MIN_SPEED, NEAR_MISS_SCORE up to NEAR_MISS_MAX_SPEED, NEAR_MISS_MAX_SCORE past it.
## Each one also counts as NEAR_MISS_COMBO_SECS of trick time, so it can open a combo on its own.
## Consts (rollback).
const NEAR_MISS_MIN_SPEED: float = 20.0
const NEAR_MISS_MAX_SPEED: float = 60.0
const NEAR_MISS_SCORE: float = 2.0
const NEAR_MISS_MAX_SCORE: float = 4.0
const NEAR_MISS_COMBO_SECS: float = 1.0
const BOOST_PER_NEAR_MISS: float = 0.25
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
## See is_air_trick. Race bots pick their air tricks from it.
const AIR_TRICKS: Array[Trick] = [
	Trick.HEEL_CLICKER,
	Trick.SPREAD_EAGLE,
	Trick.SUPERMAN,
	Trick.KICKFLIP,
	Trick.T_POSE,
	Trick.KNEE_KNOCKER,
]
## Held-trick score scale while wheelieing (_wheelie_score_mult): ramps from MIN at the wheelie
## threshold to 1 below the balance point, BP from it up; LOCKED while balance-locked. Consts (rollback).
const WHEELIE_MIN_SCORE_MULT: float = 0.5
const WHEELIE_BP_SCORE_MULT: float = 2.0
const WHEELIE_LOCKED_SCORE_MULT: float = 1.5
## Grind yaw zones (off the rail's direction): straight under ANGLED, sideways from SIDEWAYS.
## Sideways also splits pitch at HARD (slides past it). See grind_pose_trick.
const GRIND_ANGLED_YAW_DEG: float = 20.0
const GRIND_SIDEWAYS_YAW_DEG: float = 60.0
const GRIND_SIDEWAYS_HARD_PITCH_DEG: float = 30.0
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
	TrickState.GRIND:
	{
		Gesture.TAP: [Trick.NONE, Trick.HEEL_CLICKER, Trick.NONE, Trick.NONE],
		Gesture.DOUBLE_TAP: [Trick.NONE, Trick.NONE, Trick.KICKFLIP, Trick.NONE],
		Gesture.HOLD: [Trick.HIGH_CHAIR, Trick.NONE, Trick.KNEE_KNOCKER, Trick.T_POSE],
		Gesture.DOUBLE_TAP_HOLD: [Trick.NONE, Trick.NONE, Trick.NONE, Trick.NONE],
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
## Score the combo in progress has earned (see ComboRules.HELD_TRICK_SCORE / ONE_TIME_TRICK_SCORE).
## TrickManager banks it when the combo ends.
var combo_score: float = 0.0

var current_trick: Trick = Trick.NONE
var _last_trick: Trick = Trick.NONE
var _flip_emitted: bool = false # prevent re-emitting the same flip while still airborne
var _trick_timer: float = 0.0
var _wheelie_exit_hold: float = 0.0 # synced — seconds pitch has been under WHEELIE_EXIT_PITCH_DEG
## Full air rotations already paid out this airtime — synced so a resim doesn't double-award.
var _air_flips_awarded: int = 0
## Synced — last tick was a real jump (past AIR_TRICK_MIN_AIRTIME). MovementController zeroes
## air_time on the landing tick, so the landing check needs last tick's value.
var _was_airborne: bool = false
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
	# Physics-driven one-shot — rides the tap-trick latch so it stays active through the hop.
	if movement_controller.bunny_hopped:
		_tap_trick = Trick.BUNNY_HOP
		_tap_trick_timer = TAP_TRICK_DURATION
	current_trick = _detect_current_trick(delta)
	if current_trick != _last_trick:
		if _last_trick != Trick.NONE:
			trick_ended.emit(_last_trick)
		if current_trick != Trick.NONE:
			trick_started.emit(current_trick)
			ComboRules.start_trick(
				self, boost_controller, current_trick, not movement_controller.is_on_floor
			)
		_last_trick = current_trick

	_award_flip_boost()
	_award_trick_landing()
	# Here (rollback), not in TrickManager: the combo vars are netfox state properties, re-applied
	# from history every tick, so writes from a manager's _process() would never accumulate.
	ComboRules.accrue(self, boost_controller, current_trick, _wheelie_score_mult(), delta)
	# A stick trick over a grind stacks: the grind keeps scoring underneath it.
	if trick_state() == TrickState.GRIND:
		var grind := grind_pose_trick()
		if current_trick != grind:
			ComboRules.accrue_stacked(self, grind, delta)


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
	var state := trick_state()
	if state == TrickState.NONE:
		return Trick.NONE
	var trick: Trick = BINDINGS[state][gesture][dir]
	if trick == Trick.TWO_LEFT_FEET and movement_controller.speed <= TWO_LEFT_FEET_SPEED_THRESHOLD:
		return Trick.NONE
	return trick


## Which BINDINGS table applies right now, or NONE when stick tricks are gated off.
func trick_state() -> TrickState:
	# Not on the touchdown tick (still airborne): the held air trick must stay visible so landing
	# mid-trick on a rail crashes (CrashController reads it next tick).
	if movement_controller.is_grinding and movement_controller.is_on_floor:
		return TrickState.GRIND
	if not movement_controller.is_on_floor:
		# A brief hop (curb, bump) isn't a real jump — a ground trick held over a bump would
		# otherwise flick to an air trick and crash on touchdown (landed-mid-air-trick).
		if movement_controller.air_time < AIR_TRICK_MIN_AIRTIME:
			return TrickState.NONE
		return TrickState.AIR
	if movement_controller.pitch_angle > deg_to_rad(WHEELIE_PITCH_THRESHOLD_DEG):
		# Any wheelie — outside the balance point the trick still pops but throws a wobble
		# (WobbleController.trick_feed).
		return TrickState.WHEELIE
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
	if not movement_controller.is_on_floor:
		var completed := int(movement_controller.air_pitch_total / TAU)
		if completed > _air_flips_awarded:
			ComboRules.award_flips(self, boost_controller, completed - _air_flips_awarded)
			_air_flips_awarded = completed
	else:
		_air_flips_awarded = 0


## Touching down from a real jump past the wheelie / stoppie threshold banks a bonus. The landing
## tick already detected that trick, so combo time keeps running as a normal wheelie / stoppie.
func _award_trick_landing():
	if _was_airborne and is_landed_in_trick():
		ComboRules.award_landing(self, boost_controller)
	_was_airborne = (
		not movement_controller.is_on_floor
		and movement_controller.air_time >= AIR_TRICK_MIN_AIRTIME
	)


## Called from PlayerEntity's rollback tick (rb_near_miss). TrickManager only banks a combo whose
## combo_time ran, hence the time bump.
func on_near_miss(score: float):
	combo_time += NEAR_MISS_COMBO_SECS
	combo_score += score
	ComboRules.award_boost(self, boost_controller, BOOST_PER_NEAR_MISS)


static func near_miss_score(speed: float) -> float:
	if speed < NEAR_MISS_MIN_SPEED:
		return 0.0
	return NEAR_MISS_MAX_SCORE if speed > NEAR_MISS_MAX_SPEED else NEAR_MISS_SCORE


## 1 unless wheelieing; see WHEELIE_MIN_SCORE_MULT. Covers stick tricks held in a wheelie too.
func _wheelie_score_mult() -> float:
	if not (is_in_wheelie() or trick_state() == TrickState.WHEELIE):
		return 1.0
	if movement_controller.balance_locked:
		return WHEELIE_LOCKED_SCORE_MULT
	var bd = player_entity.bike_definition
	var bp_low: float = bd.wheelie_balance_point_deg - bd.wheelie_balance_point_width_deg
	var pitch_deg := rad_to_deg(movement_controller.pitch_angle)
	if pitch_deg >= bp_low:
		return WHEELIE_BP_SCORE_MULT
	var t := clampf(inverse_lerp(WHEELIE_PITCH_THRESHOLD_DEG, bp_low, pitch_deg), 0.0, 1.0)
	return lerpf(WHEELIE_MIN_SCORE_MULT, 1.0, t)


func _detect_current_trick(delta: float) -> Trick:
	# Tap trick latch overrides everything (ground or air) while it's running.
	if _tap_trick_timer > 0.0:
		return _tap_trick

	if !movement_controller.is_on_floor:
		# A bump or crest mid-trick isn't a jump — keep the ground trick (same gate as trick_state).
		if movement_controller.air_time < AIR_TRICK_MIN_AIRTIME:
			return _last_trick
		return _detect_air_trick()

	# Reset flip tracking on landing
	_flip_emitted = false

	if movement_controller.is_grinding:
		var grind_held := _held_trick()
		return grind_held if grind_held != Trick.NONE else grind_pose_trick()

	if movement_controller.is_drifting:
		# Drifting at a near-standstill is a burnout (rear spinning in place); moving is a drift.
		if movement_controller.speed < MovementController.DRIFT_MIN_SPEED:
			return Trick.BURNOUT
		if movement_controller.pitch_angle > deg_to_rad(WHEELIE_PITCH_THRESHOLD_DEG):
			_wheelie_exit_hold = 0.0
			return Trick.DRIFT_WHEELIE
		return Trick.DRIFT

	if movement_controller.pitch_angle > deg_to_rad(WHEELIE_PITCH_THRESHOLD_DEG):
		_wheelie_exit_hold = 0.0
		# Neutral stick stays the plain WHEELIE_SITTING — physics unchanged.
		var wheelie_held := _held_trick()
		if wheelie_held != Trick.NONE:
			return wheelie_held
		return Trick.WHEELIE_SITTING

	if _last_trick in [Trick.WHEELIE_SITTING, Trick.WHEELIE_MOD] and not wheelie_setting_down(delta):
		if movement_controller.pitch_angle <= deg_to_rad(WHEELIE_EXIT_PITCH_DEG):
			_wheelie_exit_hold += delta
		else:
			_wheelie_exit_hold = 0.0
		return _last_trick

	# Only a braking-held stoppie scores — a nose-down landing or coast isn't a stoppie.
	if movement_controller.is_stoppie:
		return Trick.STOPPIE

	var held := _held_trick()
	if held != Trick.NONE:
		return held

	if _last_trick == Trick.TWO_LEFT_FEET:
		if _trick_timer <= 3: # HACK - duration of the animation
			_trick_timer += delta
			return Trick.TWO_LEFT_FEET
		_trick_timer = 0

	return Trick.NONE


func _detect_air_trick() -> Trick:
	# Airborne is itself the gate — no RB. trick_state() applies the min-airtime gate; flips need
	# far more airtime than that, so it doesn't affect them.
	var held := _held_trick()
	if held != Trick.NONE:
		return held

	if not has_flipped():
		return Trick.NONE

	# Full flip completed — determine direction from pitch_angle sign
	if _flip_emitted:
		return Trick.NONE

	_flip_emitted = true
	# Latched like a tap trick: a one-tick flip is missed by per-frame pollers (tasks, HUD).
	_tap_trick = Trick.BACKFLIP if movement_controller.pitch_angle > 0 else Trick.FRONTFLIP
	_tap_trick_timer = TAP_TRICK_DURATION
	return _tap_trick


## The grind the rail pose makes. Pitch zones are the wheelie / stoppie thresholds, yaw zones
## GRIND_ANGLED_YAW_DEG / GRIND_SIDEWAYS_YAW_DEG. Each turned grind pairs left / right.
func grind_pose_trick() -> Trick:
	var pitch := movement_controller.pitch_angle
	var front := pitch < deg_to_rad(STOPPIE_PITCH_THRESHOLD_DEG)
	var back := pitch > deg_to_rad(WHEELIE_PITCH_THRESHOLD_DEG)
	var yaw := movement_controller.grind_yaw
	var left := yaw > 0.0
	if absf(yaw) >= deg_to_rad(GRIND_SIDEWAYS_YAW_DEG):
		var hard := absf(pitch) > deg_to_rad(GRIND_SIDEWAYS_HARD_PITCH_DEG)
		if front and hard:
			return Trick.NOSESLIDE if left else Trick.NOSEBLUNT
		if back and hard:
			return Trick.TAILSLIDE if left else Trick.BLUNTSLIDE
		if front:
			return Trick.WILLY if left else Trick.OVER_WILLY
		if back:
			return Trick.SMITH if left else Trick.FEEBLE
		return Trick.BOARDSLIDE if left else Trick.LIPSLIDE
	if absf(yaw) >= deg_to_rad(GRIND_ANGLED_YAW_DEG):
		if front:
			return Trick.CROOKED if left else Trick.OVERCROOK
		if back:
			return Trick.SUSKI if left else Trick.SALAD
		return Trick.SMITH if left else Trick.FEEBLE
	if front:
		return Trick.NOSEGRIND
	if back:
		return Trick.FIVE_O
	return Trick.FIFTY_FIFTY


## Called from player_entity.gd's do_respawn
func do_reset():
	# Drain any active trick so listeners (animation, camera fx, etc.) clean up
	if _last_trick != Trick.NONE:
		trick_ended.emit(_last_trick)
	current_trick = Trick.NONE
	_last_trick = Trick.NONE
	_flip_emitted = false
	_air_flips_awarded = 0
	_was_airborne = false
	_wheelie_exit_hold = 0.0
	_hold_dir = NO_DIR
	_hold_time = 0.0
	_press_double = false
	_tap_dir = NO_DIR
	_tap_age = 0.0
	_tap_trick = Trick.NONE
	_tap_trick_timer = 0.0
	ComboRules.reset(self)


func is_in_wheelie() -> bool:
	return current_trick in [Trick.WHEELIE_SITTING, Trick.WHEELIE_MOD, Trick.DRIFT_WHEELIE]


## A full flip completed this jump. air_pitch_total resets on landing, so false once grounded.
func has_flipped() -> bool:
	return movement_controller.air_pitch_total >= TAU * 0.9


## On the ground past the wheelie / stoppie threshold.
func is_landed_in_trick() -> bool:
	var pitch := movement_controller.pitch_angle
	return (
		movement_controller.is_on_floor
		and (
			pitch > deg_to_rad(WHEELIE_PITCH_THRESHOLD_DEG)
			or pitch < deg_to_rad(STOPPIE_PITCH_THRESHOLD_DEG)
		)
	)


## True while a right-stick trick (BINDINGS) runs in a ground wheelie. Reads the synced _last_trick —
## MovementController calls this before this tick's detection.
func is_wheelie_stick_trick() -> bool:
	if (
		_last_trick == Trick.NONE
		or not movement_controller.is_on_floor
		or movement_controller.pitch_angle <= deg_to_rad(WHEELIE_PITCH_THRESHOLD_DEG)
	):
		return false
	for tricks: Array in BINDINGS[TrickState.WHEELIE].values():
		if _last_trick in tricks:
			return true
	return false


## True on the tick a wheelie's WHEELIE_EXIT_DELAY runs out — the front wheel is down for good.
## MovementController reads it before this tick's _detect_current_trick, which ends the wheelie.
func wheelie_setting_down(delta: float) -> bool:
	return (
		_last_trick in [Trick.WHEELIE_SITTING, Trick.WHEELIE_MOD]
		and movement_controller.pitch_angle <= deg_to_rad(WHEELIE_EXIT_PITCH_DEG)
		and _wheelie_exit_hold + delta >= WHEELIE_EXIT_DELAY
	)


## Tricks that must be finished before touching down — landing mid-trick crashes (see
## CrashController._detect_air_trick_landing). That only checks the landing tick, so the ground
## versions of kickflip / T-pose / knee knocker stay safe.
static func is_air_trick(trick: Trick) -> bool:
	return trick in AIR_TRICKS


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
		Trick.BUNNY_HOP:
			return "BUNNY_HOP"
		Trick.DRIFT_WHEELIE:
			return "DRIFT_WHEELIE"
		Trick.FIFTY_FIFTY:
			return "FIFTY_FIFTY"
		Trick.FIVE_O:
			return "FIVE_O"
		Trick.NOSEGRIND:
			return "NOSEGRIND"
		Trick.CROOKED:
			return "CROOKED"
		Trick.FEEBLE:
			return "FEEBLE"
		Trick.SALAD:
			return "SALAD"
		Trick.BOARDSLIDE:
			return "BOARDSLIDE"
		Trick.LIPSLIDE:
			return "LIPSLIDE"
		Trick.NOSESLIDE:
			return "NOSESLIDE"
		Trick.TAILSLIDE:
			return "TAILSLIDE"
		Trick.SMITH:
			return "SMITH"
		Trick.SUSKI:
			return "SUSKI"
		Trick.OVERCROOK:
			return "OVERCROOK"
		Trick.NOSEBLUNT:
			return "NOSEBLUNT"
		Trick.BLUNTSLIDE:
			return "BLUNTSLIDE"
		Trick.WILLY:
			return "WILLY"
		Trick.OVER_WILLY:
			return "OVER_WILLY"
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
		"BUNNY_HOP":
			return Trick.BUNNY_HOP
		"DRIFT_WHEELIE":
			return Trick.DRIFT_WHEELIE
		"FIFTY_FIFTY":
			return Trick.FIFTY_FIFTY
		"FIVE_O":
			return Trick.FIVE_O
		"NOSEGRIND":
			return Trick.NOSEGRIND
		"CROOKED":
			return Trick.CROOKED
		"FEEBLE":
			return Trick.FEEBLE
		"SALAD":
			return Trick.SALAD
		"BOARDSLIDE":
			return Trick.BOARDSLIDE
		"LIPSLIDE":
			return Trick.LIPSLIDE
		"NOSESLIDE":
			return Trick.NOSESLIDE
		"TAILSLIDE":
			return Trick.TAILSLIDE
		"SMITH":
			return Trick.SMITH
		"SUSKI":
			return Trick.SUSKI
		"OVERCROOK":
			return Trick.OVERCROOK
		"NOSEBLUNT":
			return Trick.NOSEBLUNT
		"BLUNTSLIDE":
			return Trick.BLUNTSLIDE
		"WILLY":
			return Trick.WILLY
		"OVER_WILLY":
			return Trick.OVER_WILLY
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
