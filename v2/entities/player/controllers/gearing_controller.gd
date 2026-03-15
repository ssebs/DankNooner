@tool
class_name GearingController extends Node

signal gear_changed(new_gear: int)
signal rpm_updated(rpm_ratio: float)

@export var player_entity: PlayerEntity
@export var input_controller: InputController

@export var clutch_engage_speed: float = 6.0
@export var clutch_release_speed: float = 2.5
@export var clutch_tap_amount: float = 0.35

var clutch_hold_time: float = 0.0
var is_stalled: bool = false


func _ready():
	if Engine.is_editor_hint():
		return
	input_controller.clutch_held_changed.connect(_on_clutch_input)
	input_controller.gear_up_pressed.connect(_on_gear_shift.bind(1))
	input_controller.gear_down_pressed.connect(_on_gear_shift.bind(-1))


#region input handlers
## direction must be `1` or `-1` (fwd/back)
func _on_gear_shift(direction: int):
	# print("_on_gear_shift %d" % direction)
	var bd = player_entity.bike_definition
	var new_gear = clampi(player_entity.current_gear + direction, 1, bd.num_gears)
	if new_gear != player_entity.current_gear:
		player_entity.current_gear = new_gear
		gear_changed.emit(new_gear)


func _on_clutch_input(_held: bool, just_pressed: bool):
	if just_pressed:
		player_entity.clutch_value = minf(player_entity.clutch_value + clutch_tap_amount, 1.0)


#endregion


## Called from MovementController._rollback_tick()
func on_movement_rollback_tick(delta: float):
	_update_clutch_hold_time(delta)
	_blend_rpm_to_target(delta)

	player_entity.rpm_ratio = _get_rpm_ratio()
	rpm_updated.emit(player_entity.rpm_ratio)


func _update_clutch_hold_time(delta: float):
	if input_controller.nfx_clutch_held:
		clutch_hold_time += delta
		player_entity.clutch_value = move_toward(
			player_entity.clutch_value, 1.0, clutch_engage_speed * delta
		)
	else:
		clutch_hold_time = 0.0
		player_entity.clutch_value = move_toward(
			player_entity.clutch_value, 0.0, clutch_release_speed * delta
		)


func _blend_rpm_to_target(delta: float):
	var bd = player_entity.bike_definition
	var engagement = get_clutch_engagement()

	# Calculate wheel-driven RPM
	var gear_ratio = bd.gear_ratios[player_entity.current_gear - 1]
	var gear_max_speed = bd.max_speed * (bd.gear_ratios[bd.num_gears - 1] / gear_ratio)
	var speed_ratio = player_entity.speed / gear_max_speed if gear_max_speed > 0 else 0.0
	var wheel_rpm = speed_ratio * bd.max_rpm

	# Throttle-driven RPM
	var throttle_rpm = lerpf(bd.idle_rpm, bd.max_rpm, input_controller.nfx_throttle)

	# Blend based on clutch engagement
	var target_rpm = lerpf(throttle_rpm, wheel_rpm, engagement)
	player_entity.current_rpm = lerpf(player_entity.current_rpm, target_rpm, 8.0 * delta)

	# Limit RPM
	player_entity.current_rpm = clamp(player_entity.current_rpm, bd.idle_rpm, bd.max_rpm)


func _get_rpm_ratio() -> float:
	var bd = player_entity.bike_definition
	if bd.max_rpm <= bd.idle_rpm:
		return 0.0
	return (player_entity.current_rpm - bd.idle_rpm) / (bd.max_rpm - bd.idle_rpm)


#region public api
## Returns power multiplier (0-1) based on current RPM and gear
func get_power_output() -> float:
	if is_stalled:
		return 0.0

	var engagement = get_clutch_engagement()
	if engagement < 0.05:
		return 0.0

	var ratio = _get_rpm_ratio()
	var power_curve = ratio * (2.0 - ratio)  # Peaks around 75% RPM

	var bd = player_entity.bike_definition
	var gear_ratio = bd.gear_ratios[player_entity.current_gear - 1]
	var base_ratio = bd.gear_ratios[bd.num_gears - 1]
	var torque_multiplier = gear_ratio / base_ratio

	return input_controller.nfx_throttle * power_curve * torque_multiplier * engagement


func get_clutch_engagement() -> float:
	return 1.0 - player_entity.clutch_value


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if player_entity == null:
		issues.append("player_entity must not be empty")
	if input_controller == null:
		issues.append("input_controller must not be empty")
	return issues
