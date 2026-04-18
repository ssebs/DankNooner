class_name TutorialSteps extends RefCounted

## Every possible tutorial step
enum Step {
	SHOW_HELP,
	PRESS_RT,
	REACH_SPEED,
	CHANGE_GEAR,
	DO_WHEELIE,
	DO_STOPPIE,
}
# Tutorial
const THE_BASICS: Array[Step] = [
	Step.SHOW_HELP,
	Step.PRESS_RT,
	Step.REACH_SPEED,
	Step.DO_WHEELIE,
	Step.CHANGE_GEAR,
	Step.DO_STOPPIE,
]


## Inner class — one step definition
class StepDef:
	var step: Step
	var objective_text: String  # localization key
	var hint_text: String  # localization key
	var check: Callable  # (player: PlayerEntity, delta: float) -> bool
	var on_enter: Callable  # optional setup
	var on_exit: Callable  # optional cleanup
	var get_progress: Callable  # optional () -> String, shows time countup etc.


## Step registry, keyed by enum
var defs: Dictionary[Step, StepDef] = {}

## --- Duration tracking for common checks ---
var _wheelie_time: float = 0.0
var _stoppie_time: float = 0.0
var _initial_gear: int = -1
var _help_closed: bool = false


func _init():
	_register_all()


func _register_all():
	defs[Step.SHOW_HELP] = _make(
		Step.SHOW_HELP, "TUT_SHOW_HELP", "TUT_HINT_SHOW_HELP", _check_show_help, _reset_show_help
	)
	defs[Step.PRESS_RT] = _make(Step.PRESS_RT, "TUT_PRESS_RT", "TUT_HINT_PRESS_RT", _check_press_rt)
	defs[Step.REACH_SPEED] = _make(
		Step.REACH_SPEED, "TUT_REACH_SPEED", "TUT_HINT_REACH_SPEED", _check_reach_speed
	)
	defs[Step.CHANGE_GEAR] = _make(
		Step.CHANGE_GEAR,
		"TUT_CHANGE_GEAR",
		"TUT_HINT_CHANGE_GEAR",
		_check_change_gear,
		_reset_change_gear
	)
	defs[Step.DO_WHEELIE] = _make(
		Step.DO_WHEELIE,
		"TUT_DO_WHEELIE",
		"TUT_HINT_DO_WHEELIE",
		_check_wheelie,
		_reset_wheelie,
		Callable(),
		_get_wheelie_progress
	)
	defs[Step.DO_STOPPIE] = _make(
		Step.DO_STOPPIE,
		"TUT_DO_STOPPIE",
		"TUT_HINT_DO_STOPPIE",
		_check_stoppie,
		_reset_stoppie,
		Callable(),
		_get_stoppie_progress
	)


func _make(
	s, obj, hint, check, on_enter = Callable(), on_exit = Callable(), get_progress = Callable()
) -> StepDef:
	var d = StepDef.new()
	d.step = s
	d.objective_text = obj
	d.hint_text = hint
	d.check = check
	d.on_enter = on_enter
	d.on_exit = on_exit
	d.get_progress = get_progress
	return d


## ========== COMMON REUSABLE CHECKS ==========
## These can be called by any tutorial/gamemode that needs them


## Returns true if player speed > threshold (m/s)
func check_speed_above(player: PlayerEntity, threshold: float) -> bool:
	return player.movement_controller.speed > threshold


## Returns true if player speed < threshold
func check_speed_below(player: PlayerEntity, threshold: float) -> bool:
	return player.movement_controller.speed < threshold


## Returns true if active trick is a wheelie (sitting or mod)
func check_is_wheelie(player: PlayerEntity) -> bool:
	return (
		player.trick_controller.current_trick
		in [TrickController.Trick.WHEELIE_SITTING, TrickController.Trick.WHEELIE_MOD]
	)


## Returns true if active trick is a stoppie
func check_is_stoppie(player: PlayerEntity) -> bool:
	return player.trick_controller.current_trick == TrickController.Trick.STOPPIE


## ========== STEP CHECK FUNCTIONS ==========
## Each takes (player: PlayerEntity, delta: float) -> bool
## Only checks the specific peer's player, NOT all players


func _check_show_help(_player: PlayerEntity, _delta: float) -> bool:
	return _help_closed


func _check_press_rt(player: PlayerEntity, _delta: float) -> bool:
	return check_speed_above(player, 2.0)


func _check_reach_speed(player: PlayerEntity, _delta: float) -> bool:
	return check_speed_above(player, 30)  # ~30 km/h


func _check_change_gear(player: PlayerEntity, _delta: float) -> bool:
	if _initial_gear == -1:
		_initial_gear = player.gearing_controller.current_gear
	return player.gearing_controller.current_gear != _initial_gear


func _check_wheelie(_player: PlayerEntity, delta: float) -> bool:
	if check_is_wheelie(_player):
		_wheelie_time += delta
		return _wheelie_time >= 3.0
	_wheelie_time = 0.0
	return false


func _check_stoppie(_player: PlayerEntity, delta: float) -> bool:
	if check_is_stoppie(_player):
		_stoppie_time += delta
		return _stoppie_time >= 1.0
	_stoppie_time = 0.0
	return false


func _reset_show_help():
	_help_closed = false


func _reset_change_gear():
	_initial_gear = -1


func _reset_wheelie():
	_wheelie_time = 0.0


func _reset_stoppie():
	_stoppie_time = 0.0


func _get_wheelie_progress() -> String:
	return "%s\n%.1f / 3.0s" % [tr("TUT_HINT_DO_WHEELIE"), _wheelie_time]


func _get_stoppie_progress() -> String:
	return "%s\n%.1f / 1.0s" % [tr("TUT_HINT_DO_STOPPIE"), _stoppie_time]

## ========== TUTORIAL SEQUENCES ==========
## Each tutorial selects steps in order
