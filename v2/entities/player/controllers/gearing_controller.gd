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

var _clutch_hold_time: float = 0.0

var _current_gear: int = 1
var _current_rpm: float = 1000.0
var _clutch_value: float = 0.0
var _rpm_ratio: float = 0.0
var _is_stalled: bool = false


func _ready():
	if Engine.is_editor_hint():
		return
	input_controller.gear_change_pressed.connect(_on_gear_change)


#region Local input handlers
## direction must be `1` or `-1` (fwd/back)
func _on_gear_change(direction: int):
	print("_on_gear_change %d" % direction)
	var bd = player_entity.bike_definition
	var new_gear = clampi(_current_gear + direction, 1, bd.num_gears)
	if new_gear != _current_gear:
		_current_gear = new_gear
		gear_changed.emit(new_gear)


#endregion


## Called from MovementController._rollback_tick()
func on_movement_rollback_tick(delta: float):
	_update_clutch_hold_time(delta)
	_blend_rpm(delta)

	rpm_updated.emit(_get_rpm_ratio())


func _update_clutch_hold_time(delta: float):
	if input_controller.clutch_held:
		_clutch_hold_time += delta
		_clutch_value = move_toward(_clutch_value, 1.0, clutch_engage_speed * delta)
	else:
		_clutch_hold_time = 0.0
		_clutch_value = move_toward(_clutch_value, 0.0, clutch_release_speed * delta)

	print("_clutch_value: %.1f" % _clutch_value)


## Sets _current_rpm
func _blend_rpm(delta: float):
	var bd = player_entity.bike_definition
	var engagement = 1.0 - _clutch_value  # 0 = clutch in, 1 = clutch out

	# What RPM the wheel is forcing the engine to
	var gear_ratio = bd.gear_ratios[_current_gear - 1]
	var gear_max_speed = bd.max_speed * (bd.gear_ratios[bd.num_gears - 1] / gear_ratio)
	var speed_ratio = player_entity.velocity.length() / gear_max_speed if gear_max_speed > 0 else 0.0
	var wheel_rpm = lerpf(bd.idle_rpm, bd.max_rpm, speed_ratio)

	# What RPM the throttle wants
	var free_rpm = lerpf(bd.idle_rpm, bd.max_rpm, input_controller.nfx_throttle)

	# Loaded: wheel locks RPM to ground speed, throttle adds slip above it (allows starting)
	var slip_rpm = input_controller.nfx_throttle * (bd.max_rpm - bd.idle_rpm) * 0.3
	var loaded_rpm = wheel_rpm + slip_rpm

	# Blend target between free-rev and loaded based on clutch
	var target_rpm = lerpf(free_rpm, loaded_rpm, engagement)

	# Approach speed: faster when free-revving, slower when loaded
	var rising = _current_rpm <= target_rpm
	var loaded_rate = rpm_loaded_speed if rising else rpm_free_rev_speed
	var rpm_speed = lerpf(rpm_free_rev_speed, loaded_rate, engagement)

	_current_rpm = lerpf(_current_rpm, target_rpm, rpm_speed * delta)
	_current_rpm = clamp(_current_rpm, bd.idle_rpm, bd.max_rpm)
	print("RPM %.2f" % _current_rpm)


## Get pct of rpm : max rpm
func _get_rpm_ratio() -> float:
	var bd = player_entity.bike_definition
	if bd.max_rpm <= bd.idle_rpm:
		return 0.0
	return (_current_rpm - bd.idle_rpm) / (bd.max_rpm - bd.idle_rpm)


#region public api
## Returns power multiplier (0-1) based on current RPM and gear
func get_power_output() -> float:
	if _is_stalled:
		return 0.0

	var engagement = 1.0 - _clutch_value
	if _clutch_value > 0.5:
		return 0.0

	var ratio = _get_rpm_ratio()
	# TODO - use actual curve
	var power_curve = ratio * (2.0 - ratio)  # Peaks around 75% RPM

	var bd = player_entity.bike_definition
	var gear_ratio = bd.gear_ratios[_current_gear - 1]
	var base_ratio = bd.gear_ratios[bd.num_gears - 1]
	var torque_multiplier = gear_ratio / base_ratio

	var output = input_controller.nfx_throttle * power_curve * torque_multiplier * engagement
	print("power output: %.2f" % output)
	return output


## Called from player_entity.gd's do_respawn
func do_reset():
	_current_gear = 1
	_current_rpm = (
		player_entity.bike_definition.idle_rpm if player_entity.bike_definition else 1000.0
	)
	_clutch_value = 0.0
	_rpm_ratio = 0.0


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if player_entity == null:
		issues.append("player_entity must not be empty")
	if input_controller == null:
		issues.append("input_controller must not be empty")
	return issues
