@tool
## Front brake while leaned over (CrashController's washout zone) without crashing. A crash clears
## the runner's state, so it starts over.
## - PROGRESSIVE: `duration` seconds in total of hard braking while leaned. On a pad only easing in
##   survives; on a keyboard each tap adds its pressed time.
## - TRAIL: brake upright, lean in still braking, then let go while still leaned.
class_name LeanBrakeTask extends GameModeTask

enum Mode { PROGRESSIVE, TRAIL }
enum TrailStep { UPRIGHT, LEAN, RELEASE }

@export var mode: Mode = Mode.PROGRESSIVE
## PROGRESSIVE: seconds of hard braking while leaned, in total.
@export var duration: float = 1.0

## TRAIL: the brake still counts as on this long after the last press, so keyboard taps read as held.
const TRAIL_TAP_GRACE: float = 0.3
const TRAIL_STEP_KEYS: Array[String] = [
	"TUT_ADV_TRAIL_UPRIGHT", "TUT_ADV_TRAIL_LEAN", "TUT_ADV_TRAIL_RELEASE"
]


func check(player: PlayerEntity, delta: float, state: Dictionary) -> bool:
	if mode == Mode.TRAIL:
		return _check_trail(player, delta, state)
	var brake := player.input_controller.nfx_front_brake
	if _is_leaned(player) and brake > CrashController.WASHOUT_BRAKE:
		state["t"] = state.get("t", 0.0) + delta
	return state.get("t", 0.0) >= duration


func _check_trail(player: PlayerEntity, delta: float, state: Dictionary) -> bool:
	var since_brake: float = state.get("since_brake", INF) + delta
	if player.input_controller.nfx_front_brake > 0.0:
		since_brake = 0.0
	state["since_brake"] = since_brake
	var braking := since_brake <= TRAIL_TAP_GRACE
	var leaned := _is_leaned(player)
	var step: TrailStep = state.get("step", TrailStep.UPRIGHT)
	match step:
		TrailStep.UPRIGHT:
			if braking and !leaned:
				step = TrailStep.LEAN
		TrailStep.LEAN:
			if !braking:
				step = TrailStep.UPRIGHT
			elif leaned:
				step = TrailStep.RELEASE
		TrailStep.RELEASE:
			if !leaned:
				step = TrailStep.UPRIGHT
			elif !braking:
				return true
	state["step"] = step
	return false


## Leaned enough, fast enough and on the ground for a grab to wash the front out.
func _is_leaned(player: PlayerEntity) -> bool:
	var movement := player.movement_controller
	return (
		movement.is_on_floor
		and movement.speed > CrashController.WASHOUT_MIN_SPEED
		and absf(movement.roll_angle) > deg_to_rad(CrashController.WASHOUT_MIN_LEAN_DEG)
	)


func get_progress(state: Dictionary) -> String:
	if mode == Mode.TRAIL:
		return tr(TRAIL_STEP_KEYS[state.get("step", TrailStep.UPRIGHT)])
	return "%.1f / %.1fs" % [state.get("t", 0.0), duration]


func get_objective_text() -> String:
	if mode == Mode.TRAIL:
		return tr("TUT_ADV_TRAIL")
	return tr("TUT_ADV_PROGRESSIVE").format({"duration": duration})
