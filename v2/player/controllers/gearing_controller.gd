@tool
class_name GearingController extends Node

signal gear_changed(new_gear: int)
signal rpm_updated(rpm_ratio: float)

@export var player_entity: PlayerEntity
@export var input_controller: InputController

@export var clutch_engage_speed: float = 6.0
@export var clutch_release_speed: float = 2.5
@export var clutch_tap_amount: float = 0.35
@export var rpm_free_rev_speed: float = 4.0
@export var rpm_loaded_speed: float = 1.5

var current_gear: int = 1
var current_rpm: float = 1000.0
var clutch_value: float = 0.0

var is_rev_limited: bool = false
var _clutch_hold_time: float = 0.0
var _rpm_ratio: float = 0.0
var _is_stalled: bool = false


func _ready():
	if Engine.is_editor_hint():
		return
	input_controller.gear_change_pressed.connect(_on_gear_change)


## direction must be `1` or `-1` (fwd/back)
## Runs from _rollback_tick in input_controller
func _on_gear_change(direction: int):
	# DebugUtils.DebugMsg("_on_gear_change %d" % direction)
	var bd = player_entity.bike_definition
	var new_gear = clampi(current_gear + direction, 1, bd.num_gears)
	if new_gear != current_gear:
		current_gear = new_gear
		gear_changed.emit(new_gear)


## Called from MovementController._rollback_tick()
func on_movement_rollback_tick(delta: float):
	_update_clutch_hold_time(delta)
	_blend_rpm(delta)

	rpm_updated.emit(get_rpm_ratio())


func _update_clutch_hold_time(delta: float):
	if input_controller.nfx_clutch_held:
		_clutch_hold_time += delta
		clutch_value = move_toward(clutch_value, 1.0, clutch_engage_speed * delta)
	else:
		_clutch_hold_time = 0.0
		clutch_value = move_toward(clutch_value, 0.0, clutch_release_speed * delta)

	# DebugUtils.DebugMsg("clutch_value: %.1f" % clutch_value)


## Sets current_rpm
func _blend_rpm(delta: float):
	var bd = player_entity.bike_definition
	var engagement = 1.0 - clutch_value  # 0 = clutch in, 1 = clutch out

	# What RPM the wheel is forcing the engine to
	var gear_ratio = bd.gear_ratios[current_gear - 1]
	var gear_max_speed = bd.max_speed * (bd.gear_ratios[bd.num_gears - 1] / gear_ratio)
	var speed_ratio = (
		player_entity.velocity.length() / gear_max_speed if gear_max_speed > 0 else 0.0
	)
	var wheel_rpm = lerpf(bd.idle_rpm, bd.max_rpm, speed_ratio)

	# What RPM the throttle wants
	var free_rpm = lerpf(bd.idle_rpm, bd.max_rpm, input_controller.nfx_throttle)

	# Loaded: wheel locks RPM to ground speed, throttle adds slip above it (allows starting)
	var slip_rpm = input_controller.nfx_throttle * (bd.max_rpm - bd.idle_rpm) * 0.3
	var loaded_rpm = minf(wheel_rpm + slip_rpm, bd.max_rpm)

	# Blend target between free-rev and loaded based on clutch
	var target_rpm = lerpf(free_rpm, loaded_rpm, engagement)

	# Approach speed: faster when free-revving, slower when loaded
	var rising = current_rpm <= target_rpm
	var loaded_rate = rpm_loaded_speed if rising else rpm_free_rev_speed
	var rpm_speed = lerpf(rpm_free_rev_speed, loaded_rate, engagement)

	current_rpm = lerpf(current_rpm, target_rpm, rpm_speed * delta)
	current_rpm = clamp(current_rpm, bd.idle_rpm, bd.max_rpm)
	# DebugUtils.DebugMsg("RPM %.2f" % current_rpm)

	# Rev limiter — fuel cut at redline, hysteresis so RPM bounces
	if not is_rev_limited and get_rpm_ratio() >= 0.95:
		is_rev_limited = true
	elif is_rev_limited and get_rpm_ratio() < 0.9:
		is_rev_limited = false

	if is_rev_limited:
		current_rpm = lerpf(
			current_rpm,
			rpm_from_ratio(0.85),
			rpm_free_rev_speed * 5 * delta,
		)


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


## Max speed the current gear can achieve
func get_gear_max_speed() -> float:
	var bd = player_entity.bike_definition
	var gear_ratio = bd.gear_ratios[current_gear - 1]
	return bd.max_speed * (bd.gear_ratios[bd.num_gears - 1] / gear_ratio)


## Returns power multiplier (0-1) based on current RPM and gear
func get_power_output() -> float:
	if _is_stalled or is_rev_limited:
		return 0.0

	# Pulling the clutch lever is an instant disconnect
	if input_controller.nfx_clutch_held:
		return 0.0
	var engagement = 1.0 - clutch_value

	var ratio = get_rpm_ratio()
	# TODO - use actual curve
	var power_curve = ratio * (2.0 - ratio)  # Peaks around 75% RPM

	var bd = player_entity.bike_definition
	var gear_ratio = bd.gear_ratios[current_gear - 1]
	var base_ratio = bd.gear_ratios[bd.num_gears - 1]
	var torque_multiplier = gear_ratio / base_ratio

	var output = input_controller.nfx_throttle * power_curve * torque_multiplier * engagement
	# DebugUtils.DebugMsg("power output: %.2f" % output)
	return output


## Called from player_entity.gd's do_respawn
func do_reset():
	current_gear = 1
	current_rpm = (
		player_entity.bike_definition.idle_rpm if player_entity.bike_definition else 1000.0
	)
	clutch_value = 0.0
	_rpm_ratio = 0.0
	is_rev_limited = false


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if player_entity == null:
		issues.append("player_entity must not be empty")
	if input_controller == null:
		issues.append("input_controller must not be empty")
	return issues
