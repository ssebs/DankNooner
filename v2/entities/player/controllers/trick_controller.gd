@tool
class_name TrickController extends Node

signal trick_started(trick_type: int)
signal trick_ended(trick_type: int)

enum Trick { NONE, WHEELIE_SITTING, WHEELIE_MOD, STOPPIE }

@export var player_entity: PlayerEntity
@export var input_controller: InputController
@export var gearing_controller: GearingController

const CLUTCH_KICK_WINDOW: float = 0.4  # seconds after clutch dump to allow wheelie pop

var _current_trick: Trick = Trick.NONE
var _last_trick: Trick = Trick.NONE
var _clutch_kick_window: float = 0.0
var _prev_clutch_held: bool = false


func _ready():
	if Engine.is_editor_hint():
		return


## Called from MovementController._rollback_tick()
func on_movement_rollback_tick(delta: float):
	_update_current_and_last_tricks()

	if input_controller.nfx_trick_held:
		print("trick_held")

	match _current_trick:
		Trick.WHEELIE_SITTING, Trick.WHEELIE_MOD:
			_update_wheelie(delta)
		Trick.STOPPIE:
			_update_stoppie(delta)
		Trick.NONE:
			return
		_:
			print(
				(
					"_current_trick %s has no match in trick_controller on_movement_rollback_tick"
					% _current_trick
				)
			)


func _update_current_and_last_tricks():
	_current_trick = _detect_current_trick()
	if _current_trick != _last_trick:
		if _last_trick != Trick.NONE:
			trick_ended.emit(_last_trick)
		if _current_trick != Trick.NONE:
			trick_started.emit(_current_trick)
		_last_trick = _current_trick


func _detect_current_trick() -> Trick:
	if player_entity.pitch_angle > deg_to_rad(15):
		if input_controller.nfx_trick_held:
			return Trick.WHEELIE_MOD
		return Trick.WHEELIE_SITTING

	if player_entity.pitch_angle < deg_to_rad(-10):
		return Trick.STOPPIE
	return Trick.NONE


func _update_wheelie(delta: float):
	var bd = player_entity.bike_definition
	var in_wheelie = player_entity.pitch_angle > deg_to_rad(15)

	# Clutch-kick: detect clutch release this tick and open pop window if RPM was high
	var clutch_just_released = _prev_clutch_held and not input_controller.nfx_clutch_held
	_prev_clutch_held = input_controller.nfx_clutch_held
	if clutch_just_released and player_entity.rpm_ratio >= bd.wheelie_rpm_threshold:
		_clutch_kick_window = CLUTCH_KICK_WINDOW
	_clutch_kick_window = maxf(_clutch_kick_window - delta, 0.0)

	var clutch_kick = _clutch_kick_window > 0.0
	var power_wheelie = (
		player_entity.rpm_ratio >= bd.wheelie_rpm_threshold and input_controller.nfx_throttle > 0.7
	)
	var can_pop = input_controller.nfx_lean < -0.3 and (clutch_kick or power_wheelie)
	var fast_enough = player_entity.speed > 1

	var wheelie_target = 0.0
	if fast_enough and player_entity.is_on_floor() and (in_wheelie or can_pop):
		if input_controller.nfx_throttle > 0.3:
			wheelie_target = deg_to_rad(bd.max_wheelie_angle_deg) * input_controller.nfx_throttle
			if input_controller.nfx_lean < 0:
				# Leaning back adds to wheelie target
				wheelie_target += (
					deg_to_rad(bd.max_wheelie_angle_deg) * abs(input_controller.nfx_lean) * 0.15
				)

	# Apply wheelie pitch
	if wheelie_target > 0:
		player_entity.pitch_angle = move_toward(
			player_entity.pitch_angle, wheelie_target, bd.rotation_speed * delta
		)
	elif player_entity.pitch_angle > 0:
		# Return to ground, lean forward (lean > 0) helps bring wheel down
		var return_mult = 1.0
		if input_controller.nfx_lean > 0:
			return_mult = 1.0 + abs(input_controller.nfx_lean) * 2.0
		player_entity.pitch_angle = move_toward(
			player_entity.pitch_angle, 0, bd.return_speed * return_mult * delta
		)


func _update_stoppie(delta: float):
	var bd = player_entity.bike_definition
	var in_stoppie = player_entity.pitch_angle < deg_to_rad(-10)

	# Stoppie: lean forward (lean > 0 in v2) + front brake
	var wants_stoppie = input_controller.nfx_lean > 0.1 and input_controller.nfx_front_brake > 0.5

	# Scale max angle by speed
	var speed_scale = clamp(player_entity.speed / 15.0, 0.0, 1.0)
	var effective_max = deg_to_rad(bd.max_stoppie_angle_deg) * speed_scale

	var stoppie_target = 0.0
	if player_entity.speed > 1 and player_entity.is_on_floor() and (in_stoppie or wants_stoppie):
		stoppie_target = -effective_max * input_controller.nfx_front_brake

	# Apply stoppie pitch
	if stoppie_target < 0:
		player_entity.pitch_angle = move_toward(
			player_entity.pitch_angle, stoppie_target, bd.rotation_speed * delta
		)
	elif player_entity.pitch_angle < 0:
		player_entity.pitch_angle = move_toward(
			player_entity.pitch_angle, 0, bd.return_speed * delta
		)


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if player_entity == null:
		issues.append("player_entity must not be empty")
	if input_controller == null:
		issues.append("input_controller must not be empty")
	if gearing_controller == null:
		issues.append("gearing_controller must not be empty")
	return issues
