## A race bot's trick, combo and boost: the state TrickController + BoostController hold for a player,
## run by the same ComboRules. Server-simulated (NPCRaceState picks the tricks, NPCRaceManager the
## boosts); clients only get current_trick, for NPCAnimationController, and boost_burn_target, for
## BoostTrail. TrickManager banks it like a player's, through `trick_controller` on either rider.
## Idle on traffic.
class_name NPCTrickController extends Node

## Seconds a bot's flip takes; NPCRaceState only flips when the jump's airtime covers it.
const FLIP_SECS: float = 0.8

## Synced to clients.
var current_trick: TrickController.Trick = TrickController.Trick.NONE

# Same names as TrickController / BoostController, so ComboRules and TrickManager read either.
var combo_time: float = 0.0
var combo_grace: float = 0.0
var combo_boost_earned: float = 0.0
var combo_multiplier: int = 1
var combo_score: float = 0.0
var boost_amount: float = 0.0
## Synced to clients.
var boost_burn_target: float = -1.0
var boost_burn_rate: float = 0.0
var is_boosting: bool:
	get:
		return boost_burn_target >= 0.0

var _trick_left: float = 0.0


## Server. Hold trick for duration seconds. A flip pays its rotation's boost up front.
func start_trick(trick: TrickController.Trick, duration: float, airborne: bool) -> void:
	current_trick = trick
	_trick_left = duration
	ComboRules.start_trick(self, self, trick, airborne)
	if trick in [TrickController.Trick.BACKFLIP, TrickController.Trick.FRONTFLIP]:
		ComboRules.award_flips(self, self, 1)


func end_trick() -> void:
	current_trick = TrickController.Trick.NONE
	_trick_left = 0.0


## Server, every driving tick: run the trick out, accrue the combo, drain an active burn.
func tick(delta: float) -> void:
	if current_trick != TrickController.Trick.NONE:
		_trick_left -= delta
		if _trick_left <= 0.0:
			end_trick()
	ComboRules.accrue(self, self, current_trick, 1.0, delta)
	if is_boosting:
		ComboRules.drain_burn(self, self, delta)


## Server. Spends one segment, like a player's single tap; nothing under a full segment or mid-burn.
func boost() -> void:
	if boost_amount >= 1.0 and !is_boosting:
		ComboRules.burn_segment(self)


## Server, at the respawn. The crash voids what the open combo earned (as
## BoostController.apply_crash_void); banked boost survives.
func do_reset() -> void:
	boost_amount = maxf(boost_amount - combo_boost_earned, 0.0)
	boost_burn_target = -1.0
	end_trick()
	ComboRules.reset(self)
