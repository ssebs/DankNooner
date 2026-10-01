## One gas pump in a station. FuelUpGameMode assigns each rider a pump pre-race; in free roam it's
## a FreeRoamActivity. Either way the minigame runs locally on that rider's client: hold click on
## the handle to carry it, hold it over the gas cap until full, let go to hang it back up (letting
## go early just returns it). The left stick steers the same cursor, so gamepad plays it too.
class_name FuelUpMinigame extends FreeRoamActivity

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
## The cap target ring — shown only while carrying the handle.
@onready var _gas_cap_mesh: MeshInstance3D = %GasCapMeshCircle
## Shared with the start circle's "loop"; also plays "gas_cap_hover".
@onready var _anim: AnimationPlayer = %AnimationPlayer
@onready var _gas_cap_area: Area3D = %GasCapArea
## Nozzle tip's orientation once it reaches the cap.
@onready var _gas_cap_marker_tip: Marker3D = %GasCapMarkerTip
@onready var _pump_marker: Marker3D = %PumpMarker
@onready var _hose: Path3D = %Hose
@onready var _hose_mesh: CSGPolygon3D = %HoseMesh

## Tank level, 0..1. Read by FuelUpHUDState.
var fill: float = 0.0

## All set by begin() while this pump is in use.
var _player: PlayerEntity
var _input_state_manager: InputStateManager
var _audio_manager: AudioManager
var _hud_manager: HUDManager

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
## The glug plays once per fill-up; later fills resume it rather than restart it.
var _glug_started: bool = false


func _ready():
	super()
	_carry_rest = _handle_area.transform
	_tip_rel = _handle_area.global_basis.inverse() * _handle_marker_tip.global_basis
	# Own curve per pump — a scene sub_resource would be shared by every instance.
	_hose.curve = Curve3D.new()
	# Own material too, so only this pump's hose draws on top while its minigame runs.
	_hose_mesh.material = _hose_mesh.material.duplicate()
	_hose_mesh.material.no_depth_test = false
	_update_hose()
	_gas_cap_mesh.visible = false
	set_process(false)


#override
## Park the rider at bike_spot and hold them there.
func server_start(peer_id: int, spawn_manager: SpawnManager):
	spawn_manager.respawn_player_in_place.rpc(
		peer_id, bike_spot.global_position, bike_spot.global_basis
	)
	CountdownTask.freeze(spawn_manager.get_player_by_peer_id(peer_id))


#override
func server_end(peer_id: int, result: float, spawn_manager: SpawnManager):
	var player := spawn_manager.get_player_by_peer_id(peer_id)
	# The tank started at the rider's boost, so a fill-up never takes any away.
	var amount := maxf(
		player.boost_controller.boost_amount,
		clampf(result, 0.0, 1.0) * BoostController.BOOST_SEGMENTS
	)
	spawn_manager.set_boost_player.rpc(peer_id, amount)
	CountdownTask.unfreeze(player)


#override
func get_result() -> float:
	return fill


#override
## Run this pump for the local `player`, tank at their boost. Starts once their teleport onto
## bike_spot lands, since that respawn flips the HUD back to riding.
func begin(
	player: PlayerEntity,
	input_state_manager: InputStateManager,
	audio_manager: AudioManager,
	hud_manager: HUDManager
):
	_player = player
	_input_state_manager = input_state_manager
	_audio_manager = audio_manager
	_hud_manager = hud_manager
	fill = player.boost_controller.boost_amount / BoostController.BOOST_SEGMENTS
	player.respawned.connect(_start, CONNECT_ONE_SHOT)


#override
## Hand the rider back and reset the pump. Runs itself on finish; callers use it to cancel, which
## is safe even before the teleport landed.
func end():
	if _player.respawned.is_connected(_start):
		_player.respawned.disconnect(_start)
		_player = null
		return
	_input_state_manager.input_state_changed.disconnect(_on_input_state_changed)
	_input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME

	set_process(false)
	_handle_area.transform = _carry_rest
	_update_hose()
	_set_highlight(null)
	_set_cursor(null)
	_audio_manager.stop_sfx(AudioManager.Sfx.GLUG_GLUG)
	_gas_cap_mesh.visible = false
	_anim.play(&"loop")
	_hose_mesh.material.no_depth_test = false

	_player.character_skin.visible = true
	_audio_manager.play_revs(_player.bike_definition)
	_hud_manager.go_to_riding_hud()
	_player.camera_controller.switch_to_cam(_player.camera_controller.current_cam_mode)
	_player = null


func _start():
	_gas_cap_area.global_position = _player.gas_cap_marker.global_position
	_step = Step.GRAB
	_over_cap = false
	# Settles the ring at rest size (a cancel mid-hover leaves it grown); pauses the circle's loop.
	_anim.play_backwards(&"gas_cap_hover")
	_glug_started = false
	set_process(true)

	# Local only — the rider sits between the pump camera and the pump.
	_player.character_skin.visible = false
	# The pump camera would otherwise lose the hose behind the bike.
	_hose_mesh.material.no_depth_test = true
	_audio_manager.stop_revs()
	_hud_manager.go_to_fuel_up_hud(self)

	_input_state_manager.input_state_changed.connect(_on_input_state_changed)
	_input_state_manager.current_input_state = InputStateManager.InputState.IN_MINIGAME


## Unpause always lands on IN_GAME — put the cursor back while the minigame is still up.
func _on_input_state_changed(new_state: InputStateManager.InputState):
	if new_state == InputStateManager.InputState.IN_GAME:
		_input_state_manager.current_input_state = InputStateManager.InputState.IN_MINIGAME


func get_prompt_key() -> String:
	if _step == Step.GRAB:
		return "FUELUP_GRAB"
	if fill >= 1.0:
		return "FUELUP_RETURN"
	return "FUELUP_ALIGN"


func _process(delta: float):
	# Re-asserted every frame: the teleport's respawn (and its resims) and the switch-cam key
	# all hand the view back to the rider's own camera.
	camera.current = true
	# Web pointer lock lands async, so the event submit's capture can lock after IN_MINIGAME
	# released it. Asks DisplayServer since Input.mouse_mode caches the last requested mode.
	if DisplayServer.mouse_get_mode() == DisplayServer.MOUSE_MODE_CAPTURED:
		_input_state_manager.showhide_mouse_cursor()
	# Paused — the pause menu owns the cursor.
	if _input_state_manager.current_input_state != InputStateManager.InputState.IN_MINIGAME:
		_set_cursor(null)
		_set_glug(false)
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
				_set_highlight(null)
				_gas_cap_mesh.visible = true
				_step = Step.HOLD
		Step.HOLD:
			if _click_held():
				_follow_cursor()
				_set_over_cap(_tip_in_cap())
				if _over_cap:
					fill = minf(fill + delta / fill_secs, 1.0)
			else:
				# Let go: the handle springs back onto the pump.
				_handle_area.transform = _carry_rest
				_set_over_cap(false)
				_gas_cap_mesh.visible = false
				_step = Step.GRAB
				if fill >= 1.0:
					end()
					finished.emit()
					return
	_set_glug(_step == Step.HOLD and _over_cap and fill < 1.0)
	_set_cursor(CURSOR_CLOSED if _step == Step.HOLD else CURSOR_OPEN)
	_update_hose()


## Grows the cap ring while the nozzle's in it, shrinks it back on leaving.
func _set_over_cap(over: bool):
	if over == _over_cap:
		return
	_over_cap = over
	if over:
		_anim.play(&"gas_cap_hover")
	else:
		_anim.play_backwards(&"gas_cap_hover")


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


## Carry: left click (use_item) or gamepad A (ui_accept).
func _click_pressed() -> bool:
	return Input.is_action_just_pressed("use_item") or Input.is_action_just_pressed("ui_accept")


func _click_held() -> bool:
	return Input.is_action_pressed("use_item") or Input.is_action_pressed("ui_accept")


## Pausing keeps the clip's place, so filling again picks up where it left off.
func _set_glug(filling: bool):
	var glug := _audio_manager.get_sound_event(AudioManager.Sfx.GLUG_GLUG)
	if filling and !_glug_started:
		_glug_started = true
		glug.play()
	if glug.stream_paused == filling:
		glug.stream_paused = !filling


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
