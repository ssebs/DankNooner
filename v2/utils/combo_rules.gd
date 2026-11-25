## Combo + boost rules shared by the player (TrickController / BoostController, in the rollback tick)
## and race bots (NPCTrickController, server). Static-only — never instanced.
##
## Duck-typed: `combo` has combo_time, combo_grace, combo_score, combo_multiplier,
## combo_boost_earned, recent_tricks, trick_freshness, hold_secs and catch_up_mult; `boost` has
## boost_amount, boost_burn_target and boost_burn_rate. A bot passes itself as both. Consts, not
## exports: the player runs these in the rollback tick, so they must be byte-identical on every peer.
class_name ComboRules

## Boost segments earned per second of trick, before the combo multiplier. At x1 that's ~2s
## of wheelie per segment, ~6s for a full meter — short enough that a casual wheelie earns
## something usable.
const BOOST_PER_SEC: float = 0.2
## Dropping every trick starts this grace window instead of breaking the combo outright,
## so wheelie -> stoppie -> wheelie chains keep their multiplier.
const COMBO_GRACE_SECS: float = 2.5
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
## Repeat decay: a trick started again within the last RECENT_TRICK_WINDOW tricks pays (score and
## boost) REPEAT_DECAY per earlier copy, floored at MIN_FRESHNESS. A different trick pays in full.
const RECENT_TRICK_WINDOW: int = 4
const REPEAT_DECAY: float = 0.6
const MIN_FRESHNESS: float = 0.2
## Holding one trick this long drops its held score to REPEAT_DECAY; combo time keeps rising.
## EASY_HOLD_TRICKS get the short one unless held at the wheelie balance point.
const EASY_HOLD_STALE_SECS: float = 6.0
const HARD_HOLD_STALE_SECS: float = 12.0
const EASY_HOLD_TRICKS: Array[TrickController.Trick] = [
	TrickController.Trick.WHEELIE_SITTING,
	TrickController.Trick.WHEELIE_MOD,
	TrickController.Trick.STOPPIE,
	TrickController.Trick.DRIFT,
	TrickController.Trick.BURNOUT,
]
## Catch-up: trick boost fill scales by 1 + this per race place behind the leader, up to
## CATCH_UP_MAX_MULT. Set server-side (PlayerEntity.catch_up_mult).
const CATCH_UP_PER_PLACE: float = 0.2
const CATCH_UP_MAX_MULT: float = 2.0
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
	TrickController.Trick.FIFTY_FIFTY: 1.5,
	TrickController.Trick.FIVE_O: 2.0,
	TrickController.Trick.NOSEGRIND: 2.0,
	TrickController.Trick.BOARDSLIDE: 2.0,
	TrickController.Trick.LIPSLIDE: 2.0,
	TrickController.Trick.CROOKED: 2.5,
	TrickController.Trick.FEEBLE: 2.5,
	TrickController.Trick.SALAD: 2.5,
	TrickController.Trick.NOSESLIDE: 2.5,
	TrickController.Trick.TAILSLIDE: 2.5,
	TrickController.Trick.SMITH: 2.5,
	TrickController.Trick.SUSKI: 2.5,
	TrickController.Trick.OVERCROOK: 2.5,
	TrickController.Trick.NOSEBLUNT: 2.5,
	TrickController.Trick.BLUNTSLIDE: 2.5,
	TrickController.Trick.WILLY: 2.5,
	TrickController.Trick.OVER_WILLY: 2.5,
}
const ONE_TIME_TRICK_SCORE: Dictionary = {
	TrickController.Trick.HEEL_CLICKER: 1.5,
	TrickController.Trick.KICKFLIP: 3.0,
	TrickController.Trick.HEELFLIP: 3.0,
	TrickController.Trick.BS_SHUVIT: 3.0,
	TrickController.Trick.FS_SHUVIT: 3.0,
	# On top of the kickflip / heelflip they upgrade, which already banked.
	TrickController.Trick.TRE_FLIP: 5.0,
	TrickController.Trick.LAZERFLIP: 5.0,
	TrickController.Trick.BACKFLIP: 3.0,
	TrickController.Trick.FRONTFLIP: 3.0,
	TrickController.Trick.THREESIXTY: 5.0,
	TrickController.Trick.BUNNY_HOP: 4.0,
}


## Tick the combo. A held trick runs combo time, score (scaled by score_mult and freshness, and by
## REPEAT_DECAY past stale_hold_secs) and boost; with none the grace window runs down, and surviving it
## banks the combo's boost for good.
static func accrue(combo, boost, trick: TrickController.Trick, score_mult: float, delta: float) -> void:
	if trick != TrickController.Trick.NONE:
		combo.hold_secs += delta
		combo.combo_time += delta
		var stale := REPEAT_DECAY if combo.hold_secs >= stale_hold_secs(trick, score_mult) else 1.0
		combo.combo_score += HELD_TRICK_SCORE.get(trick, 0.0) * score_mult * combo.trick_freshness * stale * delta
		combo.combo_grace = COMBO_GRACE_SECS
		_add_boost(combo, boost, BOOST_PER_SEC * combo.combo_multiplier * combo.trick_freshness * delta)
	elif combo.combo_time > 0.0:
		combo.combo_grace -= delta
		if combo.combo_grace <= 0.0:
			end_combo(combo)

	var mult := 1
	for threshold in COMBO_MULT_THRESHOLDS:
		if combo.combo_time >= threshold:
			mult += 1
	combo.combo_multiplier = mult


## A held trick scoring underneath the current one (a grind under a stick trick), so stacking pays
## both. Combo time and boost already run from accrue().
static func accrue_stacked(combo, trick: TrickController.Trick, delta: float) -> void:
	combo.combo_score += HELD_TRICK_SCORE[trick] * delta


## A trick just started: its freshness, its one-time score, plus a chunk of boost for an air trick
## (void-on-crash means you must land it clean).
static func start_trick(combo, boost, trick: TrickController.Trick, airborne: bool) -> void:
	# The wheelie variants are one hold
	var key := TrickController.Trick.WHEELIE_SITTING if trick in TrickController.WHEELIE_TRICKS else trick
	var recent: PackedInt32Array = combo.recent_tricks
	# A held trick flickering off and back on mid-combo (a drift's slip, a nose bobbing at the
	# threshold) is the same hold: no repeat, and its hold time keeps running.
	if combo.combo_time > 0.0 and HELD_TRICK_SCORE.has(trick) and !recent.is_empty() and recent[-1] == key:
		return
	combo.trick_freshness = maxf(pow(REPEAT_DECAY, recent.count(key)), MIN_FRESHNESS)
	recent.append(key)
	if recent.size() > RECENT_TRICK_WINDOW:
		recent.remove_at(0)
	combo.recent_tricks = recent
	combo.hold_secs = 0.0
	combo.combo_score += ONE_TIME_TRICK_SCORE.get(trick, 0.0) * combo.trick_freshness
	if airborne and TrickController.is_air_trick(trick):
		award_boost(combo, boost, BOOST_PER_AIR_TRICK * combo.trick_freshness)


## How long `trick` can be held before its held score drops. score_mult > 1 means a
## wheelie at its balance point (TrickController._wheelie_score_mult).
static func stale_hold_secs(trick: TrickController.Trick, score_mult: float) -> float:
	if trick in EASY_HOLD_TRICKS and score_mult <= 1.0:
		return EASY_HOLD_STALE_SECS
	return HARD_HOLD_STALE_SECS


## Ends the combo cleanly: TrickManager banks it, and its boost is permanent.
static func end_combo(combo) -> void:
	combo.combo_time = 0.0
	combo.combo_grace = 0.0
	combo.combo_score = 0.0
	combo.combo_boost_earned = 0.0


## Boost fill multiplier for being `places_behind` the race leader.
static func catch_up_mult(places_behind: int) -> float:
	return minf(1.0 + CATCH_UP_PER_PLACE * places_behind, CATCH_UP_MAX_MULT)


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


## catch_up_mult is the server's race standing, so it survives.
static func reset(combo) -> void:
	combo.combo_time = 0.0
	combo.combo_grace = 0.0
	combo.combo_boost_earned = 0.0
	combo.combo_multiplier = 1
	combo.combo_score = 0.0
	combo.recent_tricks = PackedInt32Array()
	combo.trick_freshness = 1.0
	combo.hold_secs = 0.0


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


## Post-cap, so topping out a full meter doesn't inflate the claim a crash voids. Scaled by the
## catch-up mult: every trick-earned chunk fills faster for a rider behind.
static func _add_boost(combo, boost, amount: float) -> void:
	var before: float = boost.boost_amount
	boost.boost_amount = minf(before + amount * combo.catch_up_mult, BoostController.BOOST_SEGMENTS)
	combo.combo_boost_earned += boost.boost_amount - before
