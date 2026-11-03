## Combo + boost rules shared by the player (TrickController / BoostController, in the rollback tick)
## and race bots (NPCTrickController, server). Static-only — never instanced.
##
## Duck-typed: `combo` has combo_time, combo_grace, combo_score, combo_multiplier and
## combo_boost_earned; `boost` has boost_amount, boost_burn_target and boost_burn_rate. A bot passes
## itself as both. Consts, not exports: the player runs these in the rollback tick, so they must be
## byte-identical on every peer.
class_name ComboRules

## Boost segments earned per second of trick, before the combo multiplier. At x1 that's ~2s
## of wheelie per segment, ~6s for a full meter — short enough that a casual wheelie earns
## something usable.
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
const BOOST_PER_FLIP: float = 0.5
const BOOST_PER_AIR_TRICK: float = 0.5
## One-time score for touching down from a real jump straight into a wheelie or stoppie. Its boost
## reuses BOOST_PER_AIR_TRICK.
const LANDING_TRICK_SCORE: float = 3.0
## Per-trick score, in "seconds at TrickManager.points_per_second". Held tricks earn their value per
## second while active; one-time tricks bank it once, when they start.
const HELD_TRICK_SCORE: Dictionary = {
	TrickController.Trick.WHEELIE_SITTING: 1.0,
	TrickController.Trick.WHEELIE_MOD: 1.0,
	TrickController.Trick.STOPPIE: 1.0,
	TrickController.Trick.DRIFT: 0.75,
	TrickController.Trick.BURNOUT: 0.5,
	TrickController.Trick.DRIFT_WHEELIE: 2.0,
	TrickController.Trick.HIGH_CHAIR: 1.5,
	TrickController.Trick.KNEE_KNOCKER: 1.5,
	TrickController.Trick.T_POSE: 1.5,
	TrickController.Trick.TWO_LEFT_FEET: 1.5,
	TrickController.Trick.SPREAD_EAGLE: 2.0,
	TrickController.Trick.SUPERMAN: 2.0,
}
const ONE_TIME_TRICK_SCORE: Dictionary = {
	TrickController.Trick.HEEL_CLICKER: 1.5,
	TrickController.Trick.KICKFLIP: 3.0,
	TrickController.Trick.BACKFLIP: 5.0,
	TrickController.Trick.FRONTFLIP: 5.0,
	TrickController.Trick.THREESIXTY: 5.0,
	TrickController.Trick.BUNNY_HOP: 4.0,
}


## Tick the combo. A held trick runs combo time, score (scaled by score_mult) and boost; with none
## the grace window runs down, and surviving it banks the combo's boost for good.
static func accrue(combo, boost, trick: TrickController.Trick, score_mult: float, delta: float) -> void:
	if trick != TrickController.Trick.NONE:
		combo.combo_time += delta
		combo.combo_score += HELD_TRICK_SCORE.get(trick, 0.0) * score_mult * delta
		combo.combo_grace = COMBO_GRACE_SECS
		_add_boost(combo, boost, BOOST_PER_SEC * combo.combo_multiplier * delta)
	elif combo.combo_time > 0.0:
		combo.combo_grace -= delta
		if combo.combo_grace <= 0.0:
			combo.combo_time = 0.0
			combo.combo_grace = 0.0
			combo.combo_score = 0.0
			combo.combo_boost_earned = 0.0

	var mult := 1
	for threshold in COMBO_MULT_THRESHOLDS:
		if combo.combo_time >= threshold:
			mult += 1
	combo.combo_multiplier = mult


## A trick just started: its one-time score, plus a chunk of boost for an air trick (void-on-crash
## means you must land it clean).
static func start_trick(combo, boost, trick: TrickController.Trick, airborne: bool) -> void:
	combo.combo_score += ONE_TIME_TRICK_SCORE.get(trick, 0.0)
	if airborne and TrickController.is_air_trick(trick):
		award_boost(combo, boost, BOOST_PER_AIR_TRICK)


static func award_flips(combo, boost, flips: int) -> void:
	award_boost(combo, boost, BOOST_PER_FLIP * flips)


## Touched down from a real jump straight into a wheelie or stoppie.
static func award_landing(combo, boost) -> void:
	combo.combo_score += LANDING_TRICK_SCORE
	award_boost(combo, boost, BOOST_PER_AIR_TRICK)


## A lump of trick boost, scaled by the multiplier. Keeps the combo alive so chained tricks build it.
static func award_boost(combo, boost, base: float) -> void:
	_add_boost(combo, boost, base * combo.combo_multiplier)
	combo.combo_grace = COMBO_GRACE_SECS


static func reset(combo) -> void:
	combo.combo_time = 0.0
	combo.combo_grace = 0.0
	combo.combo_boost_earned = 0.0
	combo.combo_multiplier = 1
	combo.combo_score = 0.0


## +1 segment, clamped to full (Gas Can).
static func add_segment(boost) -> void:
	boost.boost_amount = minf(boost.boost_amount + 1.0, BoostController.BOOST_SEGMENTS)


## Commit a one-segment burn: a single boost tap.
static func burn_segment(boost) -> void:
	boost.boost_burn_target = boost.boost_amount - 1.0
	boost.boost_burn_rate = 1.0 / BoostController.BOOST_SEGMENT_SECS


## Drain the active burn, ending it at its target. The open combo's claim drops with the meter, or a
## later crash would eat previously banked boost too.
static func drain_burn(combo, boost, delta: float) -> void:
	var before: float = boost.boost_amount
	boost.boost_amount = maxf(boost.boost_amount - boost.boost_burn_rate * delta, boost.boost_burn_target)
	combo.combo_boost_earned = maxf(combo.combo_boost_earned - (before - boost.boost_amount), 0.0)
	if boost.boost_amount <= boost.boost_burn_target:
		boost.boost_burn_target = -1.0


## Post-cap, so topping out a full meter doesn't inflate the claim a crash voids.
static func _add_boost(combo, boost, amount: float) -> void:
	var before: float = boost.boost_amount
	boost.boost_amount = minf(before + amount, BoostController.BOOST_SEGMENTS)
	combo.combo_boost_earned += boost.boost_amount - before
