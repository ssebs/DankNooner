## One gas pump in a station. FuelUpGameMode assigns each rider a pump pre-race; in free roam it's
## a FreeRoamActivity. Either way the minigame runs locally on that rider's client: click the
## handle to pick it up, hold click to spray (recoil kicks the cursor), move it back onto the pump
## to hang it up, and click %EndBtn to finish whenever. Spray not going into an unfull tank is
## spilled, and spilled gas is tank space lost: the tank only fills to 1 - spilled. The left
## stick steers the same cursor, so gamepad plays it too.
class_name FuelUpMinigame extends FreeRoamActivity

enum Step { GRAB, CARRY }

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
## %EndBtn's material while hovered.
const HOVER_GLOW := preload("res://levels/assets/props/neon_blue.tres")
## Upward recoil (px/s) on the cursor while spraying, scaled up by each second of spray.
const RECOIL_RISE: float = 40.0
## Random recoil kicks: size (px), and mean seconds between them.
const RECOIL_KICK_PX: float = 25.0
const RECOIL_KICK_SECS: float = 0.25
## How close (m) the grip must come back to its spot on the pump to hang up.
const HANG_UP_DIST: float = 0.25

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
@onready var _spill_particles: GPUParticles3D = %SpillParticles
@onready var _end_btn: Area3D = %EndBtn
@onready var _end_btn_mesh: MeshInstance3D = %EndBtnMesh

## Tank level, 0..1 - spilled. Read by FuelUpHUDState.
var fill: float = 0.0
## Gas spilled this fill-up, in fill's units. Read by FuelUpGameMode.
var spilled: float = 0.0

var _step := Step.GRAB
var _over_cap: bool = false
var _spraying: bool = false
var _spray_secs: float = 0.0
## The grip starts on its hanging spot, so hanging up waits until it has been carried off it.
var _left_rest: bool = false
## View-axis depth the handle keeps while it follows the cursor.
var _hold_depth: float = 0.0
## Grip-to-cap distance at grab; the swing toward the cap pose is measured against it.
var _grab_dist: float = 0.0
## Grip's hanging spot on the pump, taken at grab.
var _rest_grip: Vector3
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
func server_end(peer_id: int, result: float, spawn_manager: SpawnManager):
	var player := spawn_manager.get_player_by_peer_id(peer_id)
	# The tank started at the rider's boost, so a fill-up never takes any away.
	var amount := maxf(
		player.boost_controller.boost_amount,
		clampf(result, 0.0, 1.0) * BoostController.BOOST_SEGMENTS
	)
	spawn_manager.set_boost_player.rpc(peer_id, amount)
	super(peer_id, result, spawn_manager)


#override
func get_result() -> float:
	return fill


#override
## Run this pump for the local `player`, tank at their boost.
func begin(
	player: PlayerEntity,
	input_state_manager: InputStateManager,
	audio_manager: AudioManager,
	hud_manager: HUDManager
):
	fill = player.boost_controller.boost_amount / BoostController.BOOST_SEGMENTS
	super(player, input_state_manager, audio_manager, hud_manager)


#override
func _on_session_start():
	_gas_cap_area.global_position = _player.gas_cap_marker.global_position
	_step = Step.GRAB
	_over_cap = false
	_spraying = false
	spilled = 0.0
	# Settles the ring at rest size (a cancel mid-hover leaves it grown); pauses the circle's loop.
	_anim.play_backwards(&"gas_cap_hover")
	_glug_started = false
	set_process(true)

	# Local only — the rider sits between the pump camera and the pump.
	_player.character_skin.visible = false
	# The pump camera would otherwise lose the hose behind the bike.
	_hose_mesh.material.no_depth_test = true
	_hud_manager.go_to_fuel_up_hud(self)


#override
## Reset the pump.
func _on_session_end():
	set_process(false)
	_handle_area.transform = _carry_rest
	_update_hose()
	_set_highlight(null)
	_end_btn_mesh.set_surface_override_material(0, null)
	_set_cursor(null)
	_audio_manager.stop_sfx(AudioManager.Sfx.GLUG_GLUG)
	_set_spilling(false)
	_gas_cap_mesh.visible = false
	_anim.play(&"loop")
	_hose_mesh.material.no_depth_test = false

	_player.character_skin.visible = true
	_hud_manager.go_to_riding_hud()


func get_prompt_key() -> String:
	if _step == Step.GRAB:
		return "FUELUP_GRAB"
	if _is_spilling():
		return "FUELUP_SPILLING"
	if _is_full():
		return "FUELUP_RETURN"
	return "FUELUP_ALIGN"


func _process(delta: float):
	# Web pointer lock lands async, so the event submit's capture can lock after IN_MINIGAME
	# released it. Asks DisplayServer since Input.mouse_mode caches the last requested mode.
	if DisplayServer.mouse_get_mode() == DisplayServer.MOUSE_MODE_CAPTURED:
		_input_state_manager.showhide_mouse_cursor()
	# Paused — the pause menu owns the cursor.
	if _input_state_manager.current_input_state != InputStateManager.InputState.IN_MINIGAME:
		_set_cursor(null)
		_set_glug(false)
		_set_spilling(false)
		return
	_move_cursor_with_stick(delta)
	match _step:
		Step.GRAB:
			var hovered := _hovered_area()
			_set_highlight(_handle if hovered == _handle_area else null)
			_end_btn_mesh.set_surface_override_material(
				0, HOVER_GLOW if hovered == _end_btn else null
			)
			if hovered == _end_btn and _click_pressed():
				end()
				finished.emit()
				return
			if hovered == _handle_area and _click_pressed():
				_rest_grip = _handle_marker_click.global_position
				_hold_depth = -camera.to_local(_rest_grip).z
				_grab_dist = _rest_grip.distance_to(_gas_cap_area.global_position)
				_solve_swing()
				_set_highlight(null)
				_gas_cap_mesh.visible = true
				_left_rest = false
				_step = Step.CARRY
		Step.CARRY:
			_follow_cursor()
			_set_over_cap(_tip_in_cap())
			# Holding on past the grab sprays (and spills), which teaches riders to let go.
			_spraying = _click_held()
			if _spraying:
				_spray(delta)
			else:
				_spray_secs = 0.0
			var on_rest := (
				_handle_marker_click.global_position.distance_to(_rest_grip) < HANG_UP_DIST
			)
			_left_rest = _left_rest or !on_rest
			if _left_rest and on_rest and !_spraying:
				_handle_area.transform = _carry_rest
				_set_over_cap(false)
				_gas_cap_mesh.visible = false
				_step = Step.GRAB
	_set_glug(_spraying and _over_cap and !_is_full())
	_set_spilling(_is_spilling())
	_set_cursor(CURSOR_CLOSED if _step == Step.CARRY else CURSOR_OPEN)
	_update_hose()


## One frame of spray: into the tank if the tip's in an unfull one, else spilled. Recoil shoves the
## cursor itself (so the rider pulls back to where they were), harder the longer it sprays. Web
## ignores warp_mouse, so it has no recoil.
func _spray(delta: float):
	_spray_secs += delta
	var recoil := Vector2.UP * RECOIL_RISE * (1.0 + _spray_secs) * delta
	if randf() < delta / RECOIL_KICK_SECS:
		recoil += Vector2(randf_range(-1.0, 1.0), -randf()) * RECOIL_KICK_PX
	_nudge_cursor(recoil)
	if _over_cap and !_is_full():
		fill = minf(fill + delta / fill_secs, 1.0 - spilled)
	else:
		spilled += delta / fill_secs
		# Overfilling a full tank spills what's already in it.
		fill = minf(fill, 1.0 - spilled)


func _is_spilling() -> bool:
	return _spraying and !(_over_cap and !_is_full())


## Filled to the space spilling left.
func _is_full() -> bool:
	return fill >= 1.0 - spilled


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
	_nudge_cursor(stick * gamepad_cursor_speed * delta)


func _nudge_cursor(offset: Vector2):
	var viewport := get_viewport()
	var pos := viewport.get_mouse_position() + offset
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


## Grab, spray and end: left click (use_item) or gamepad A (ui_accept).
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


func _set_spilling(spilling: bool):
	_spill_particles.emitting = spilling
	var splash := _audio_manager.get_sound_event(AudioManager.Sfx.WATER_FLOWING)
	if splash.playing != spilling:
		if spilling:
			splash.play()
		else:
			splash.stop()


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
