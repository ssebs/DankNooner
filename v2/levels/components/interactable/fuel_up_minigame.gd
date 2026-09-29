## One gas pump in a station. FuelUpGameMode assigns each rider a pump and runs its minigame
## locally on that rider's client: hold click on the handle to carry it, hold fill over the gas cap
## until full, let go to hang it back up (letting go early just returns it). The left stick steers
## the same cursor, so gamepad plays it too.
class_name FuelUpMinigame extends Node3D

signal finished

enum Step { GRAB, HOLD }

## Seconds of held fill from empty to full.
@export var fill_secs: float = 3.0
## Cursor speed (px/s) at full left-stick tilt.
@export var gamepad_cursor_speed: float = 900.0

## Short enough that picking only reaches this pump, never its neighbours.
const PICK_RAY_LENGTH: float = 4.0
const PICK_LAYER_MASK: int = 32 # 1 << 5 (layer 6 "interactable")
## How far the fake hose droops between the pump and the handle.
const HOSE_SAG: float = 0.5
const CURSOR_OPEN := preload("res://levels/components/interactable/cursors/hand_open.png")
const CURSOR_CLOSED := preload("res://levels/components/interactable/cursors/hand_closed.png")
const CURSOR_HOTSPOT := Vector2(32, 32)

@onready var camera: Camera3D = %Camera3D
## Where the assigned rider's bike is parked.
@onready var bike_spot: Marker3D = %BikeSpot
@onready var _handle: GrayBoxStaticBody = %Handle
@onready var _handle_marker_hose: Marker3D = %HandleMarkerHose
## Grip point — held under the cursor.
@onready var _handle_marker_click: Marker3D = %HandleMarkerClick
@onready var _handle_marker_tip: Marker3D = %HandleMarkerTip
## The whole handle assembly (handle + nozzle) is carried by moving this.
@onready var _handle_area: Area3D = %HandleArea
@onready var _gas_cap: GrayBoxStaticBody = %GasCap
@onready var _gas_cap_area: Area3D = %GasCapArea
## Nozzle tip's orientation once it reaches the cap.
@onready var _gas_cap_marker_tip: Marker3D = %GasCapMarkerTip
@onready var _pump_marker: Marker3D = %PumpMarker
@onready var _hose: Path3D = %Hose

## Tank level, 0..1. Read by FuelUpHUDState.
var fill: float = 0.0
## Set by FuelUpGameMode while this pump is in use.
var input_state_manager: InputStateManager

var _step := Step.GRAB
var _over_cap: bool = false
## View-axis depth the handle keeps while it follows the cursor.
var _hold_depth: float = 0.0
## Grip-to-cap distance at grab; the swing toward the cap pose is measured against it.
var _grab_dist: float = 0.0
var _carry_rest: Transform3D
## Tip basis relative to HandleArea — fixed, so the carry basis that lines the tip up with
## GasCapMarkerTip can be solved for.
var _tip_rel: Basis
## World-space swing from the hanging pose to the cap pose, solved at grab.
var _swing_axis: Vector3
var _swing_angle: float = 0.0
## Grip height that puts the tip at the cap in the cap pose; the carry plane eases to it.
var _cap_grip_height: float = 0.0
var _cursor: Texture2D
var _highlighted: GrayBoxStaticBody


func _ready():
	_carry_rest = _handle_area.transform
	_tip_rel = _handle_area.global_basis.inverse() * _handle_marker_tip.global_basis
	# Own curve per pump — a scene sub_resource would be shared by every instance.
	_hose.curve = Curve3D.new()
	_update_hose()
	set_process(false)


## Begin on this client, tank already at start_fill (the rider's boost), cap target moved onto
## the rider's bike.
func start(start_fill: float, gas_cap_pos: Vector3):
	fill = start_fill
	_gas_cap_area.global_position = gas_cap_pos
	_step = Step.GRAB
	_over_cap = false
	set_process(true)


## Reset the pump for its next use.
func stop():
	set_process(false)
	_handle_area.transform = _carry_rest
	_update_hose()
	_set_highlight(null)
	_set_cursor(null)


func get_prompt_key() -> String:
	if _step == Step.GRAB:
		return "FUELUP_GRAB"
	if fill >= 1.0:
		return "FUELUP_RETURN"
	return "FUELUP_FILL" if _over_cap else "FUELUP_ALIGN"


func _process(delta: float):
	# Re-asserted every frame: the teleport's respawn (and its resims) and the switch-cam key
	# all hand the view back to the rider's own camera.
	camera.current = true
	# Paused — the pause menu owns the cursor.
	if input_state_manager.current_input_state != InputStateManager.InputState.IN_MINIGAME:
		_set_cursor(null)
		return
	_move_cursor_with_stick(delta)
	match _step:
		Step.GRAB:
			var hovered := _hovered_area()
			_set_highlight(_handle if hovered == _handle_area else null)
			if hovered == _handle_area and _click_pressed():
				_hold_depth = -camera.to_local(_handle_marker_click.global_position).z
				_grab_dist = _handle_marker_click.global_position.distance_to(
					_gas_cap_area.global_position
				)
				_solve_swing()
				_step = Step.HOLD
		Step.HOLD:
			if _click_held():
				_follow_cursor()
				_over_cap = _tip_in_cap()
				_set_highlight(_gas_cap if _over_cap else null)
				if _over_cap and Input.is_action_pressed("fuel_fill"):
					fill = minf(fill + delta / fill_secs, 1.0)
			else:
				# Let go: the handle springs back onto the pump.
				_handle_area.transform = _carry_rest
				_set_highlight(null)
				_over_cap = false
				_step = Step.GRAB
				if fill >= 1.0:
					stop()
					finished.emit()
					return
	_set_cursor(CURSOR_CLOSED if _step == Step.HOLD else CURSOR_OPEN)
	_update_hose()


## Fake hose: a bezier from the pump to the handle, both ends drooping.
func _update_hose():
	var sag := Vector3.DOWN * HOSE_SAG
	_hose.curve.clear_points()
	_hose.curve.add_point(_hose.to_local(_pump_marker.global_position), Vector3.ZERO, sag)
	_hose.curve.add_point(_hose.to_local(_handle_marker_hose.global_position), sag, Vector3.ZERO)


func _move_cursor_with_stick(delta: float):
	var stick := Input.get_vector("steer_left", "steer_right", "lean_forward", "lean_back")
	if stick == Vector2.ZERO:
		return
	var viewport := get_viewport()
	var pos := viewport.get_mouse_position() + stick * gamepad_cursor_speed * delta
	viewport.warp_mouse(pos.clamp(Vector2.ZERO, viewport.get_visible_rect().size))


## This pump's Area3D under the cursor, or null.
func _hovered_area() -> Area3D:
	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var query := PhysicsRayQueryParameters3D.create(
		from, from + camera.project_ray_normal(mouse) * PICK_RAY_LENGTH
	)
	query.collision_mask = PICK_LAYER_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = false
	return get_world_3d().direct_space_state.intersect_ray(query).get("collider") as Area3D


## Whether the nozzle tip is inside the gas cap's hitbox.
func _tip_in_cap() -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = _handle_marker_tip.global_position
	query.collision_mask = PICK_LAYER_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for hit in get_world_3d().direct_space_state.intersect_point(query):
		if hit.collider == _gas_cap_area:
			return true
	return false


## Grip under the cursor, swinging from hanging on the pump to the tip lined up with
## GasCapMarkerTip as the cursor nears the cap.
func _follow_cursor():
	var mouse := get_viewport().get_mouse_position()
	var cursor := camera.project_position(mouse, _hold_depth)
	var cap_dist := cursor.distance_to(_gas_cap_area.global_position)
	var near := 1.0 - clampf(cap_dist / _grab_dist, 0.0, 1.0)
	# Nearing the cap, ride the level plane that holds the tip at cap height instead of the
	# camera-facing one, so the nozzle doesn't sink into the bike. null = cursor above the horizon.
	var on_cap_plane = Plane(Vector3.UP, _cap_grip_height).intersects_ray(
		camera.project_ray_origin(mouse), camera.project_ray_normal(mouse)
	)
	if on_cap_plane != null:
		cursor = cursor.lerp(on_cap_plane, near)
	var swing := Basis(Quaternion(_swing_axis, _swing_angle * near))
	_handle_area.global_basis = swing * global_basis * _carry_rest.basis
	var grip_offset := _handle_marker_click.global_position - _handle_area.global_position
	_handle_area.global_position = cursor - grip_offset


## Called while the handle still hangs at rest. A near half-turn is ambiguous either way round
## (slerp picked toward the camera), so take whichever way swings the nozzle away from it.
func _solve_swing():
	var rest_basis := global_basis * _carry_rest.basis
	var cap_basis := _gas_cap_marker_tip.global_basis * _tip_rel.inverse()
	var swing := Quaternion(cap_basis * rest_basis.inverse())
	_swing_axis = swing.get_axis().normalized()
	_swing_angle = swing.get_angle()
	if _swing_angle > PI:
		_swing_axis = -_swing_axis
		_swing_angle = TAU - _swing_angle
	var nozzle := _handle_marker_tip.global_position - _handle_marker_click.global_position
	var halfway := nozzle.rotated(_swing_axis, _swing_angle * 0.5)
	if halfway.dot(-camera.global_basis.z) < 0.0:
		_swing_axis = -_swing_axis
		_swing_angle = TAU - _swing_angle
	var grip_from_tip := _handle_marker_click.global_position - _handle_marker_tip.global_position
	_cap_grip_height = (
		_gas_cap_area.global_position.y + (cap_basis * (rest_basis.inverse() * grip_from_tip)).y
	)


## Carry: left click (use_item) or gamepad A (ui_accept). Fill is its own action (fuel_fill).
func _click_pressed() -> bool:
	return Input.is_action_just_pressed("use_item") or Input.is_action_just_pressed("ui_accept")


func _click_held() -> bool:
	return Input.is_action_pressed("use_item") or Input.is_action_pressed("ui_accept")


func _set_cursor(tex: Texture2D):
	if tex == _cursor:
		return
	_cursor = tex
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, CURSOR_HOTSPOT)


func _set_highlight(body: GrayBoxStaticBody):
	if body == _highlighted:
		return
	if _highlighted != null:
		_highlighted.neon_edges = false
	_highlighted = body
	if body != null:
		body.neon_edges = true
