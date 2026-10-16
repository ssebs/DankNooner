extends RefCounted
## Inputs that perform each TrickController.Trick, closed-loop on the local rider's state.
## Stick tricks are derived from TrickController.BINDINGS, so a new binding needs no recipe here.
## Air tricks need the caller to be driving at a ramp.

## [UP, DOWN, LEFT, RIGHT], matching TrickController.Dir
const DIR_ACTIONS: Array[StringName] = [&"cam_up", &"cam_down", &"cam_left", &"cam_right"]
## Easiest state first: ground tricks only need the trick button held
const STATE_PREFERENCE: Array[int] = [
	TrickController.TrickState.GROUND,
	TrickController.TrickState.WHEELIE,
	TrickController.TrickState.AIR,
]
## Stick flick length, well inside TrickController.TAP_TRICK_MAX_SECS / DOUBLE_TAP_WINDOW
const TAP_SECS := 0.08
## A gesture that didn't land is retried this often
const GESTURE_RETRY_SECS := 1.2
## Wheelie height held, as a fraction of the bike's balance point
const WHEELIE_FRAC := 0.5
const HOP_WHEELIE_FRAC := 0.3
## Lean per radian of wheelie pitch error
const LEAN_GAIN := 3.0
## Clutch-pop cycle: rev with the clutch in for POP_REV_SECS, dump it, retry each POP_CYCLE_SECS
const POP_REV_SECS := 0.4
const POP_CYCLE_SECS := 1.5
## Speed fraction a stoppie brakes from (MovementController's auto stoppie needs 0.6)
const STOPPIE_SPEED_FRAC := 0.65
## Drift entry speed band: above DRIFT_MIN_SPEED, below the brake-entry wobble
const DRIFT_ENTRY_SPEED := 15.0
const DRIFT_MAX_SPEED_FRAC := 0.45

var _t := 0.0


func reset() -> void:
	_t = 0.0


## Writes this frame's inputs for `trick` into `inputs` (action -> strength), on top of the
## caller's throttle and steering. False when nothing can perform `trick`.
func drive(trick: int, player: PlayerEntity, inputs: Dictionary, delta: float) -> bool:
	_t += delta
	var binding := _stick_binding(trick)
	if !binding.is_empty():
		_stick_trick(binding, player, inputs)
		return true
	match trick:
		TrickController.Trick.WHEELIE_SITTING:
			_wheelie(player, inputs, WHEELIE_FRAC)
		TrickController.Trick.STOPPIE:
			_stoppie(player, inputs)
		TrickController.Trick.DRIFT:
			_drift(player, inputs)
		TrickController.Trick.BURNOUT:
			_burnout(player, inputs)
		TrickController.Trick.DRIFT_WHEELIE:
			_drift_wheelie(player, inputs)
		TrickController.Trick.BUNNY_HOP:
			_bunny_hop(player, inputs)
		TrickController.Trick.BACKFLIP:
			_flip(player, inputs, &"lean_back")
		TrickController.Trick.FRONTFLIP:
			_flip(player, inputs, &"lean_forward")
		_:
			return false
	return true


## The first BINDINGS slot holding `trick`: {state, gesture, dir}, or {} for a physics trick.
func _stick_binding(trick: int) -> Dictionary:
	for state in STATE_PREFERENCE:
		var gestures: Dictionary = TrickController.BINDINGS[state]
		for gesture in gestures:
			var dir: int = (gestures[gesture] as Array).find(trick)
			if dir != -1:
				return {"state": state, "gesture": gesture, "dir": dir}
	return {}


func _stick_trick(binding: Dictionary, player: PlayerEntity, inputs: Dictionary) -> void:
	match binding["state"]:
		TrickController.TrickState.GROUND:
			inputs[&"trick"] = 1.0
		TrickController.TrickState.WHEELIE:
			_wheelie(player, inputs, WHEELIE_FRAC)
	# Air: the caller is driving at the ramp; the gesture waits for the jump
	if player.trick_controller.trick_state() != binding["state"]:
		_t = 0.0
		return
	var t := fmod(_t, GESTURE_RETRY_SECS)
	var pressed := false
	match binding["gesture"]:
		TrickController.Gesture.TAP:
			pressed = t < TAP_SECS
		TrickController.Gesture.DOUBLE_TAP:
			pressed = t < TAP_SECS or (t >= 2.0 * TAP_SECS and t < 3.0 * TAP_SECS)
		TrickController.Gesture.HOLD:
			pressed = true
		TrickController.Gesture.DOUBLE_TAP_HOLD:
			pressed = t < TAP_SECS or t >= 2.0 * TAP_SECS
	if pressed:
		inputs[DIR_ACTIONS[binding["dir"]]] = 1.0


## Holds the front up at `frac` of the balance point; clutch-pops it up first.
func _wheelie(player: PlayerEntity, inputs: Dictionary, frac: float) -> void:
	var pitch := player.movement_controller.pitch_angle
	var target := deg_to_rad(player.bike_definition.wheelie_balance_point_deg * frac)
	inputs[&"throttle_pct"] = 1.0
	if pitch < deg_to_rad(TrickController.WHEELIE_PITCH_THRESHOLD_DEG):
		inputs[&"lean_back"] = 1.0
		if fmod(_t, POP_CYCLE_SECS) < POP_REV_SECS:
			inputs[&"clutch"] = 1.0
		return
	_lean(inputs, (pitch - target) * LEAN_GAIN)


func _stoppie(player: PlayerEntity, inputs: Dictionary) -> void:
	var mc := player.movement_controller
	if mc.speed_pct < STOPPIE_SPEED_FRAC and !mc.is_stoppie:
		return  # build speed on the caller's throttle
	inputs[&"throttle_pct"] = 0.0
	inputs[&"brake_front_pct"] = 1.0
	inputs[&"lean_forward"] = 0.5


func _drift(player: PlayerEntity, inputs: Dictionary) -> void:
	var mc := player.movement_controller
	if !mc.is_drifting:
		if mc.speed < DRIFT_ENTRY_SPEED:
			return
		if mc.speed_pct > DRIFT_MAX_SPEED_FRAC:
			inputs[&"throttle_pct"] = 0.0
			return
	inputs[&"brake_rear"] = 1.0
	inputs[&"steer_left"] = 0.0
	inputs[&"steer_right"] = 1.0


## Stop, rev against the front brake with the clutch in, then dump it.
func _burnout(player: PlayerEntity, inputs: Dictionary) -> void:
	var mc := player.movement_controller
	if mc.speed > 1.0 and !mc.is_drifting:
		inputs[&"throttle_pct"] = 0.0
		inputs[&"brake_front_pct"] = 1.0
		return
	inputs[&"throttle_pct"] = 1.0
	inputs[&"brake_front_pct"] = 1.0
	inputs[&"lean_forward"] = 1.0
	var revved := (
		player.gearing_controller.get_rpm_ratio() > MovementController.BURNOUT_MIN_RPM_RATIO
	)
	if !mc.is_drifting and !revved:
		inputs[&"clutch"] = 1.0


func _drift_wheelie(player: PlayerEntity, inputs: Dictionary) -> void:
	if !player.movement_controller.is_drifting:
		_drift(player, inputs)
		return
	inputs[&"brake_rear"] = 0.0
	inputs[&"steer_right"] = 1.0
	_wheelie(player, inputs, WHEELIE_FRAC)


## A low wheelie, then gas off + lean forward pops the hop.
func _bunny_hop(player: PlayerEntity, inputs: Dictionary) -> void:
	var balance := player.bike_definition.wheelie_balance_point_deg
	var pitch := player.movement_controller.pitch_angle
	var in_wheelie := player.trick_controller.current_trick == TrickController.Trick.WHEELIE_SITTING
	if !in_wheelie or pitch > deg_to_rad(balance * MovementController.HOP_MAX_BALANCE_FRAC):
		_wheelie(player, inputs, HOP_WHEELIE_FRAC)
		return
	inputs[&"throttle_pct"] = 0.0
	inputs[&"lean_back"] = 0.0
	inputs[&"lean_forward"] = 1.0


func _flip(player: PlayerEntity, inputs: Dictionary, lean_action: StringName) -> void:
	if !player.movement_controller.is_on_floor:
		inputs[lean_action] = 1.0


## Positive leans forward
func _lean(inputs: Dictionary, value: float) -> void:
	value = clampf(value, -1.0, 1.0)
	inputs[&"lean_forward"] = maxf(value, 0.0)
	inputs[&"lean_back"] = maxf(-value, 0.0)
