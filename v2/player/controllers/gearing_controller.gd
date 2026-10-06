@tool
class_name GearingController extends Node

signal gear_changed(new_gear: int)
signal rpm_updated(rpm_ratio: float)

@export var player_entity: PlayerEntity
@export var input_controller: InputController

const CLUTCH_ENGAGE_SPEED: float = 6.0
const CLUTCH_RELEASE_SPEED: float = 2.5
const CLUTCH_TAP_AMOUNT: float = 0.35
const RPM_FREE_REV_SPEED: float = 12.0
## RPM ratio the limiter drops to on a redline cut. Lower = longer, more audible bounce.
const REV_LIMIT_CUT_RATIO: float = 0.85

var current_gear: int = 1:
	# Resim can restore a gear from before a mid-race bike swap (Rally Up) the new bike lacks.
	set(value):
		current_gear = clampi(value, 1, player_entity.bike_definition.num_gears)
var current_rpm: float = 1000.0
var clutch_value: float = 0.0

var is_rev_limited: bool = false
var shift_cut_timer: float = 0.0
var _clutch_hold_time: float = 0.0
var _rpm_ratio: float = 0.0
var _is_stalled: bool = false


## Apply the synced requested gear from InputController. Absolute-valued (not edge-triggered)
## so netfox stale-input reuse / dropped snapshots can't skip or double-apply shifts.
func _apply_target_gear():
	var bd = player_entity.bike_definition
	var new_gear = clampi(input_controller.nfx_target_gear, 1, bd.num_gears)
	if new_gear != current_gear:
		current_gear = new_gear
		shift_cut_timer = bd.shift_cut_time
		gear_changed.emit(new_gear)


## Called from PlayerEntity._rollback_tick()
func on_movement_rollback_tick(delta: float):
	shift_cut_timer = maxf(shift_cut_timer - delta, 0.0)
	_apply_target_gear()
	_update_clutch_hold_time(delta)
	_blend_rpm(delta)

	rpm_updated.emit(get_rpm_ratio())


func _update_clutch_hold_time(delta: float):
	if input_controller.nfx_clutch_held:
		_clutch_hold_time += delta
		clutch_value = move_toward(clutch_value, 1.0, CLUTCH_ENGAGE_SPEED * delta)
	else:
		_clutch_hold_time = 0.0
		clutch_value = move_toward(clutch_value, 0.0, CLUTCH_RELEASE_SPEED * delta)

	# DebugUtils.DebugMsg("clutch_value: %.1f" % clutch_value)


## Sets current_rpm
func _blend_rpm(delta: float):
	var bd = player_entity.bike_definition
	var engagement = 1.0 - clutch_value # 0 = clutch in, 1 = clutch out

	# RPM locked to wheel speed via gear ratio
	var gear_ratio = bd.gear_ratios[current_gear - 1]
	var gear_max_speed = bd.max_speed * (bd.gear_ratios[bd.num_gears - 1] / gear_ratio)
	var speed_ratio = (
		player_entity.velocity.length() / gear_max_speed if gear_max_speed > 0 else 0.0
	)
	var wheel_rpm = lerpf(bd.idle_rpm, bd.max_rpm, clampf(speed_ratio, 0.0, 1.0))

	# Free-rev RPM from throttle (clutch pulled)
	var free_rpm = lerpf(bd.idle_rpm, bd.max_rpm, input_controller.nfx_throttle)
	# Climb rate follows the power curve (quick through the band, lazy off idle); spin-down uses base rate
	var rev_speed = RPM_FREE_REV_SPEED
	if free_rpm > current_rpm:
		rev_speed *= bd.power_curve.sample(get_rpm_ratio())
	var smooth_free = lerpf(current_rpm, free_rpm, rev_speed * delta)

	# Engaged = locked to wheel speed, disengaged = free-rev
	var target_rpm = lerpf(smooth_free, wheel_rpm, engagement)
	if shift_cut_timer > 0.0:
		# Glide to the new gear's RPM over the shift cut instead of snapping
		target_rpm = lerpf(current_rpm, target_rpm, 1.0 - shift_cut_timer / bd.shift_cut_time)
	current_rpm = clamp(target_rpm, bd.idle_rpm, bd.max_rpm)
	# DebugUtils.DebugMsg("RPM %.2f" % current_rpm)

	# Rev limiter — fuel cut at redline, instant drop to simulate ignition cut
	if not is_rev_limited and get_rpm_ratio() >= 0.98:
		is_rev_limited = true
		current_rpm = rpm_from_ratio(REV_LIMIT_CUT_RATIO)
	elif is_rev_limited and get_rpm_ratio() < 0.96:
		is_rev_limited = false


#region public api
## Get pct of rpm : max rpm
func get_rpm_ratio() -> float:
	var bd = player_entity.bike_definition
	if bd.max_rpm <= bd.idle_rpm:
		return 0.0
	return (current_rpm - bd.idle_rpm) / (bd.max_rpm - bd.idle_rpm)


## Convert a 0-1 ratio back to an RPM value
func rpm_from_ratio(ratio: float) -> float:
	var bd = player_entity.bike_definition
	return bd.idle_rpm + (bd.max_rpm - bd.idle_rpm) * ratio


## Max speed `gear` can achieve
func get_gear_max_speed(gear: int) -> float:
	var bd = player_entity.bike_definition
	var gear_ratio = bd.gear_ratios[gear - 1]
	return bd.max_speed * (bd.gear_ratios[bd.num_gears - 1] / gear_ratio)


## Returns power multiplier (0-1) based on current RPM and gear
func get_power_output() -> float:
	if _is_stalled or is_rev_limited or shift_cut_timer > 0.0:
		return 0.0

	# Pulling the clutch lever is an instant disconnect
	if input_controller.nfx_clutch_held:
		return 0.0
	var engagement = 1.0 - clutch_value

	var ratio = get_rpm_ratio()
	var bd = player_entity.bike_definition
	var power_curve = bd.power_curve.sample(ratio)

	var gear_ratio = bd.gear_ratios[current_gear - 1]
	var base_ratio = bd.gear_ratios[bd.num_gears - 1]
	var torque_multiplier = gear_ratio / base_ratio

	var output = input_controller.nfx_throttle * power_curve * torque_multiplier * engagement
	# DebugUtils.DebugMsg("power output: %.2f" % output)
	return output


## Power output ignoring clutch engagement — used to gate clutch-dump wheelies,
## since at the moment of release clutch_value is still ~1.0 and engagement ~0.
func get_potential_power_output() -> float:
	if _is_stalled or is_rev_limited or shift_cut_timer > 0.0:
		return 0.0
	var ratio = get_rpm_ratio()
	var bd = player_entity.bike_definition
	var power_curve = bd.power_curve.sample(ratio)
	var gear_ratio = bd.gear_ratios[current_gear - 1]
	var base_ratio = bd.gear_ratios[bd.num_gears - 1]
	var torque_multiplier = gear_ratio / base_ratio
	return input_controller.nfx_throttle * power_curve * torque_multiplier


## Called from player_entity.gd's do_respawn
func do_reset():
	current_gear = 1
	current_rpm = (
		player_entity.bike_definition.idle_rpm if player_entity.bike_definition else 1000.0
	)
	clutch_value = 0.0
	_rpm_ratio = 0.0
	is_rev_limited = false
	shift_cut_timer = 0.0


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if player_entity == null:
		issues.append("player_entity must not be empty")
	if input_controller == null:
		issues.append("input_controller must not be empty")
	return issues
