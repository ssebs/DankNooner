extends Node
## Presses this peer's inputs for its own rider, on the director's orders. Goes through
## Input.action_press, which InputController._gather records like a human's input.
##
## Order: {"mode": "idle" | "hold" | "go", "target": Vector3 or null, "trick": int, "gear": bool}
##   hold = throttle only (what a player does at a countdown); go = drive at `target` (straight
##   ahead when null) while performing `trick`, tapping gear up once if `gear`.

const TrickRecipes := preload("res://tests/trick_recipes.gd")
const IDLE := {"mode": "idle"}
## Every action the bot drives; anything else is left alone
const ACTIONS: Array[StringName] = [
	&"throttle_pct", &"brake_front_pct", &"brake_rear", &"steer_left", &"steer_right",
	&"lean_forward", &"lean_back", &"trick", &"clutch", &"gear_up",
	&"cam_left", &"cam_right", &"cam_up", &"cam_down",
]
## Heading error that gets full steering lock
const FULL_STEER_ANGLE := PI / 6.0
## Past this heading error and speed the bot brakes into the turn instead of throttling
const SHARP_TURN_ANGLE := PI / 2.0
const SHARP_TURN_SPEED := 15.0

var order: Dictionary = IDLE

## Set by the TestRunner, for reporting a trick no recipe can do
var violate: Callable

var _recipes := TrickRecipes.new()
var _gear_tapped := false
var _reported_trick := -1
## This frame's action -> strength
var _inputs: Dictionary = {}


func set_order(new_order: Dictionary) -> void:
	if new_order.get("trick", -1) != order.get("trick", -1):
		_recipes.reset()
	if !new_order.get("gear", false):
		_gear_tapped = false
	order = new_order


func _physics_process(delta: float) -> void:
	_inputs.clear()
	# No local rider in menus, mid-load or mid-rejoin — nothing to drive is intentional
	var player := get_tree().get_first_node_in_group(UtilsConstants.GROUPS["LocalPlayer"])
	if player != null:
		match order["mode"]:
			"hold":
				_inputs[&"throttle_pct"] = 1.0
			"go":
				_go(player as PlayerEntity, delta)
	for action in ACTIONS:
		var strength: float = _inputs.get(action, 0.0)
		if strength > 0.0:
			Input.action_press(action, strength)
		elif Input.is_action_pressed(action):
			Input.action_release(action)


func _go(player: PlayerEntity, delta: float) -> void:
	_inputs[&"throttle_pct"] = 1.0
	if order.get("target") != null:
		_steer_to(player, order["target"])
	if order.get("gear", false) and !_gear_tapped:
		_inputs[&"gear_up"] = 1.0
		_gear_tapped = true
	var trick: int = order.get("trick", TrickController.Trick.NONE)
	if trick == TrickController.Trick.NONE:
		return
	if !_recipes.drive(trick, player, _inputs, delta) and _reported_trick != trick:
		_reported_trick = trick
		violate.call("no input recipe performs %s" % TrickController.trick_to_str(trick))


func _steer_to(player: PlayerEntity, target: Vector3) -> void:
	var forward := -player.global_basis.z
	forward.y = 0.0
	var to_target := target - player.global_position
	to_target.y = 0.0
	# Positive = target on the left
	var error := forward.signed_angle_to(to_target, Vector3.UP)
	var steer := clampf(-error / FULL_STEER_ANGLE, -1.0, 1.0)
	_inputs[&"steer_right"] = maxf(steer, 0.0)
	_inputs[&"steer_left"] = maxf(-steer, 0.0)
	if absf(error) > SHARP_TURN_ANGLE and player.movement_controller.speed > SHARP_TURN_SPEED:
		_inputs[&"throttle_pct"] = 0.0
		_inputs[&"brake_front_pct"] = 0.6
