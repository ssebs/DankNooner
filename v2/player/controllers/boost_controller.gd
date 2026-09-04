@tool
## Owns the boost meter: commit-on-press burn mechanics + the synced meter state.
## Earned by TrickController's combo accrual, spent here, banked by TrickManager.
## Runs inside the rollback tick — see planning_docs/ComboAndBoost.md.
class_name BoostController extends Node

@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var trick_controller: TrickController

# Boost — earned from tricks (TrickManager), spent here. Drained in the rollback tick so the
# local client predicts it and netfox reconciles against the server's meter.
# The meter is 3 discrete segments (boost_amount is in segments, 0..3). A press commits to
# burning the current segment down to the next boundary — releasing early does NOT cancel.
const BOOST_SEGMENTS: float = 5.0
const BOOST_SEGMENT_SECS: float = 1.0  # one segment = 1s of boost, spent piecemeal
const BOOST_FULL_BURN_SECS: float = 4.0  # a full meter burned in one press runs longer
const BOOST_ACCEL_MULT: float = 1.8  # engine drive multiplier while boosting
const BOOST_SPEED_MULT: float = 1.25  # raises both the gear cap and bd.max_speed ceiling

## Boost meter in SEGMENTS, 0..BOOST_SEGMENTS. Filled server-side by TrickManager from trick
## points; drained here in the rollback tick, so the local client predicts the drain and
## netfox reconciles it against the server.
var boost_amount: float = 0.0
## Meter level the active burn is running down to, or -1 when not boosting. A press commits
## to reaching this, so releasing the button early can't cancel the boost.
var boost_burn_target: float = -1.0
## Segments per second of the active burn (a full-meter commit burns slower / lasts longer).
var boost_burn_rate: float = 0.0
## Previous tick's nfx_boost_held — synced so the rising edge survives netfox resimulation.
var boost_prev_held: bool = false
## Derived each rollback tick from the burn state. Drives speed + boost FX.
var is_boosting: bool = false


## Called FIRST from PlayerEntity._rollback_tick — ahead of every other controller AND
## evaluated while crashed, so a crash mid-boost cancels the burn (and its camera FX)
## instead of leaving it latched until the respawn.
##
## Drain the boost meter and resolve is_boosting for this tick. TrickManager owns filling it
## (server, outside rollback); everything here derives from synced input + synced meter state,
## so it resimulates cleanly.
##
## A press burns the current segment down to the next boundary and can't be cancelled by
## releasing — pressing on a full meter instead commits all three at once for a longer boost.
func on_movement_rollback_tick(delta: float):
	var held := input_controller.nfx_boost_held
	var was_held := boost_prev_held
	boost_prev_held = held

	if player_entity.is_crashed:
		boost_burn_target = -1.0
		is_boosting = false
		return

	# Rising edge with at least one whole segment banked commits a burn.
	if held and not was_held and boost_burn_target < 0.0 and boost_amount >= 1.0:
		if boost_amount >= BOOST_SEGMENTS:
			boost_burn_target = 0.0
			boost_burn_rate = BOOST_SEGMENTS / BOOST_FULL_BURN_SECS
		else:
			# Spend exactly one segment — BOOST_SEGMENT_SECS of boost per press.
			boost_burn_target = boost_amount - 1.0
			boost_burn_rate = 1.0 / BOOST_SEGMENT_SECS

	is_boosting = boost_burn_target >= 0.0
	if !is_boosting:
		return

	var before: float = boost_amount
	boost_amount = maxf(boost_amount - boost_burn_rate * delta, boost_burn_target)
	# Draw the in-progress combo's claim down alongside the meter, or spending would leave a
	# claim larger than what's left and a later crash would eat previously banked boost too.
	trick_controller.combo_boost_earned = maxf(
		trick_controller.combo_boost_earned - (before - boost_amount), 0.0
	)
	if boost_amount <= boost_burn_target:
		boost_burn_target = -1.0


## +1 segment, clamped to full. Called from PlayerEntity's rollback tick (rb_add_boost) so the
## write to the synced boost_amount survives resimulation. Gas Can pickup.
func add_segment():
	boost_amount = minf(boost_amount + 1.0, BOOST_SEGMENTS)


## A crash voids only what the in-progress combo earned — boost banked by earlier completed
## combos survives. Called from PlayerEntity._apply_respawn_state BEFORE the do_reset loop
## clears trick_controller.combo_boost_earned.
func apply_crash_void(earned: float):
	boost_amount = maxf(boost_amount - earned, 0.0)


## Called from player_entity.gd's do_respawn. boost_amount deliberately survives — banked
## boost is yours across respawns; only the active burn resets.
func do_reset():
	boost_burn_target = -1.0
	boost_burn_rate = 0.0
	boost_prev_held = false
	is_boosting = false


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if player_entity == null:
		issues.append("player_entity must not be empty")
	if input_controller == null:
		issues.append("input_controller must not be empty")
	if trick_controller == null:
		issues.append("trick_controller must not be empty")

	return issues
