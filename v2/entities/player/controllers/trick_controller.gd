@tool
class_name TrickController extends Node

signal trick_started(trick_type: int)
signal trick_ended(trick_type: int)
signal boost_started
signal boost_ended

enum Trick { NONE, WHEELIE_SITTING, WHEELIE_STANDING, STOPPIE, FISHTAIL }

@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var gearing_controller: GearingController

@export var boost_duration: float = 2.0
@export var boost_speed_multiplier: float = 1.5

const CLUTCH_KICK_WINDOW: float = 0.4  # seconds after clutch dump to allow wheelie pop

var _boost_timer: float = 0.0
var _last_trick: Trick = Trick.NONE
var _clutch_kick_window: float = 0.0
var _prev_clutch_held: bool = false


func _ready():
	if Engine.is_editor_hint():
		return


## Called from MovementController._rollback_tick()
func on_movement_rollback_tick(delta: float):
	_update_wheelie(delta)
	_update_stoppie(delta)
	_update_boost(delta)
	_detect_trick_changes()


func _update_wheelie(delta: float):
	var bd = player_entity.bike_definition
	var in_wheelie = player_entity.pitch_angle > deg_to_rad(15)

	# Clutch-kick: detect clutch release this tick and open pop window if RPM was high
	var clutch_just_released = _prev_clutch_held and not input_controller.clutch_held
	_prev_clutch_held = input_controller.clutch_held
	if clutch_just_released and player_entity.rpm_ratio >= bd.wheelie_rpm_threshold:
		_clutch_kick_window = CLUTCH_KICK_WINDOW
	_clutch_kick_window = maxf(_clutch_kick_window - delta, 0.0)

	var clutch_kick = _clutch_kick_window > 0.0
	var power_wheelie = (
		player_entity.rpm_ratio >= bd.wheelie_rpm_threshold and input_controller.throttle > 0.7
	)
	var can_pop = input_controller.lean < -0.3 and (clutch_kick or power_wheelie)
	var fast_enough = player_entity.speed > 1

	var wheelie_target = 0.0
	if fast_enough and player_entity.is_on_floor() and (in_wheelie or can_pop):
		if input_controller.throttle > 0.3:
			wheelie_target = deg_to_rad(bd.max_wheelie_angle_deg) * input_controller.throttle
			if input_controller.lean < 0:
				# Leaning back adds to wheelie target
				wheelie_target += (
					deg_to_rad(bd.max_wheelie_angle_deg) * abs(input_controller.lean) * 0.15
				)

	# Apply wheelie pitch
	if wheelie_target > 0:
		player_entity.pitch_angle = move_toward(
			player_entity.pitch_angle, wheelie_target, bd.rotation_speed * delta
		)
	elif player_entity.pitch_angle > 0:
		# Return to ground, lean forward (lean > 0) helps bring wheel down
		var return_mult = 1.0
		if input_controller.lean > 0:
			return_mult = 1.0 + abs(input_controller.lean) * 2.0
		player_entity.pitch_angle = move_toward(
			player_entity.pitch_angle, 0, bd.return_speed * return_mult * delta
		)


func _update_stoppie(delta: float):
	var bd = player_entity.bike_definition
	var in_stoppie = player_entity.pitch_angle < deg_to_rad(-10)

	# Stoppie: lean forward (lean > 0 in v2) + front brake
	var wants_stoppie = input_controller.lean > 0.1 and input_controller.front_brake > 0.5

	# Scale max angle by speed
	var speed_scale = clamp(player_entity.speed / 15.0, 0.0, 1.0)
	var effective_max = deg_to_rad(bd.max_stoppie_angle_deg) * speed_scale

	var stoppie_target = 0.0
	if player_entity.speed > 1 and player_entity.is_on_floor() and (in_stoppie or wants_stoppie):
		stoppie_target = -effective_max * input_controller.front_brake

	# Apply stoppie pitch
	if stoppie_target < 0:
		player_entity.pitch_angle = move_toward(
			player_entity.pitch_angle, stoppie_target, bd.rotation_speed * delta
		)
	elif player_entity.pitch_angle < 0:
		player_entity.pitch_angle = move_toward(
			player_entity.pitch_angle, 0, bd.return_speed * delta
		)


func _update_boost(delta: float):
	if not player_entity.is_boosting:
		return

	_boost_timer -= delta
	if _boost_timer <= 0:
		player_entity.is_boosting = false
		boost_ended.emit()


func activate_boost():
	if player_entity.is_boosting or player_entity.boost_count <= 0:
		return

	player_entity.boost_count -= 1
	player_entity.is_boosting = true
	_boost_timer = boost_duration
	boost_started.emit()


func get_effective_max_speed() -> float:
	var bd = player_entity.bike_definition
	if player_entity.is_boosting:
		return bd.max_speed * boost_speed_multiplier
	return bd.max_speed


func _detect_trick_changes():
	var current = _detect_current_trick()
	if current != _last_trick:
		if _last_trick != Trick.NONE:
			trick_ended.emit(_last_trick)
		if current != Trick.NONE:
			trick_started.emit(current)
		_last_trick = current


func _detect_current_trick() -> Trick:
	if player_entity.pitch_angle > deg_to_rad(15):
		if input_controller.trick:
			return Trick.WHEELIE_STANDING
		return Trick.WHEELIE_SITTING
	elif player_entity.pitch_angle < deg_to_rad(-10):
		return Trick.STOPPIE
	elif abs(player_entity.fishtail_angle) > deg_to_rad(10):
		return Trick.FISHTAIL
	return Trick.NONE


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if player_entity == null:
		issues.append("player_entity must not be empty")
	if input_controller == null:
		issues.append("input_controller must not be empty")
	if gearing_controller == null:
		issues.append("gearing_controller must not be empty")
	return issues
