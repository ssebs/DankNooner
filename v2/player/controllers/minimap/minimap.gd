@tool
## Client-side HUD minimap: a real orthographic top-down Camera3D in a
## SubViewport (sharing the live World3D) that follows the local player
## heading-up, with racer blips drawn as a 2D overlay on top.
##
## Dormant until activate() — only the local player's HUD turns it on
## (see HUDController.show_hud), so remote player instances never render it.
class_name Minimap extends PanelContainer

## Camera ortho size — world units across the minimap view (zoom).
@export var zoom: float = 120.0
## Camera height above the player, in metres.
@export var height: float = 80.0
@export var dot_radius: float = 5.0
## Black ring thickness around each blip.
@export var border_width: float = 2.0
## Length of the edge pointer triangle for off-map racers.
@export var arrow_size: float = 6.0
## Blip redraw rate. The map camera still follows every frame — only the overlay throttles.
## Each blip is two draw_circle calls, so at 100+ racers this pass cost several ms a frame,
## and blips do not need 60Hz.
@export var blip_refresh_hz: float = 20.0

@export_group("Full Map")
## Ortho size (world units across) the full map opens at — much more zoomed out than the minimap.
@export var full_zoom: float = 500.0
@export var full_zoom_min: float = 150.0
@export var full_zoom_max: float = 1500.0
## Gamepad pan rate, as a fraction of the current view height per second (scales with zoom).
@export var map_pan_rate: float = 0.6

const COLOR_SELF := Color.WHITE
const COLOR_PLAYER := Color(0.2, 0.5, 1.0)
const COLOR_NPC := Color(0.7, 0.3, 1.0)
const COLOR_CHECKPOINT := Color(0.15, 0.85, 0.2)
const COLOR_EVENT := Color(1.0, 0.1, 0.8)

@onready var _sub_viewport: SubViewport = %MinimapSubViewport
@onready var _camera: Camera3D = %MinimapCamera
@onready var _dot_overlay: Control = %DotOverlay

var _local_player: PlayerEntity
var _active: bool = false
## Next-checkpoint marker for the local racer — server-fed via rpc_set_checkpoint
## (checkpoint progress is server-only), null while not racing.
var _checkpoint_pos: Vector3
var _has_checkpoint: bool = false
var _blip_timer: float = 0.0
## Full-map state: expanded to fullscreen + free-pan (north-up) instead of heading-up follow.
var _expanded: bool = false
var _pan_center: Vector3
## Layout snapshot restored on collapse (the minimap lives at a fixed corner offset).
var _saved_anchors: Array
var _saved_offsets: Array
var _saved_offset_transform


func _ready():
	_camera.size = zoom
	_dot_overlay.draw.connect(_draw_dots)
	set_process(false)


## Turn the minimap on for the local player. Called from HUDController.show_hud,
## which only runs on the local client.
func activate(local_player: PlayerEntity) -> void:
	_local_player = local_player
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_active = true
	set_process(true)


## Toggle between the corner minimap (heading-up follow) and the fullscreen pannable
## map (north-up). Driven by HUDController off the IN_MAP input state.
func set_expanded(on: bool) -> void:
	if on == _expanded:
		return
	_expanded = on
	if on:
		_pan_center = _local_player.global_position
		_camera.size = clampf(full_zoom, full_zoom_min, full_zoom_max)
		_saved_anchors = [anchor_left, anchor_top, anchor_right, anchor_bottom]
		_saved_offsets = [offset_left, offset_top, offset_right, offset_bottom]
		_saved_offset_transform = get("offset_transform_enabled")
		set("offset_transform_enabled", false)
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		move_to_front()
	else:
		_camera.size = zoom
		set("offset_transform_enabled", _saved_offset_transform)
		anchor_left = _saved_anchors[0]
		anchor_top = _saved_anchors[1]
		anchor_right = _saved_anchors[2]
		anchor_bottom = _saved_anchors[3]
		offset_left = _saved_offsets[0]
		offset_top = _saved_offsets[1]
		offset_right = _saved_offsets[2]
		offset_bottom = _saved_offsets[3]


## Full-map only: left-drag pans, wheel zooms. HUD controls are mouse-filter IGNORE, so
## these events fall through to here rather than being eaten by the overlay.
func _unhandled_input(event: InputEvent) -> void:
	if !_expanded or !_active:
		return
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		# Grab-drag: screen pixels → world units (ortho size is the view's vertical extent).
		# Screen-up is world -Z, so drag moves the view opposite the cursor.
		var world_per_px := _camera.size / _sub_viewport.size.y
		_pan_center.x -= event.relative.x * world_per_px
		_pan_center.z -= event.relative.y * world_per_px
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.size = clampf(_camera.size * 0.9, full_zoom_min, full_zoom_max)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.size = clampf(_camera.size * 1.1, full_zoom_min, full_zoom_max)


func _process(delta: float):
	if !_active:
		return

	if _expanded:
		_update_full_map_camera(delta)
	else:
		_update_follow_camera()

	# Camera follows every frame so the map itself stays smooth; only the blip overlay
	# throttles. The overlay keeps its last drawn frame in between.
	_blip_timer -= delta
	if _blip_timer <= 0.0:
		_blip_timer = 1.0 / blip_refresh_hz
		_dot_overlay.queue_redraw()


## Heading-up follow: look straight down at the player; player's forward becomes screen-up.
## Bike front is -Z (Godot convention, matches NPC rig).
func _update_follow_camera() -> void:
	var player_fwd := -_local_player.global_transform.basis.z
	player_fwd.y = 0.0
	var cam_pos := _local_player.global_position + Vector3.UP * height
	_camera.look_at_from_position(cam_pos, _local_player.global_position, player_fwd)


## North-up free-pan: look straight down at the pan target, world -Z as screen-up.
## Gamepad pans via the camera stick (reused); mouse drag/scroll is in _unhandled_input.
func _update_full_map_camera(delta: float) -> void:
	var stick := Vector2(
		Input.get_axis("cam_left", "cam_right"), Input.get_axis("cam_up", "cam_down")
	)
	_pan_center += Vector3(stick.x, 0.0, stick.y) * map_pan_rate * _camera.size * delta
	var target := Vector3(_pan_center.x, 0.0, _pan_center.z)
	_camera.look_at_from_position(target + Vector3.UP * height, target, Vector3.FORWARD)


## Runs during the overlay's draw pass (connected to its `draw` signal), so the
## draw calls target the overlay canvas item on top of the SubViewport.
func _draw_dots() -> void:
	# The overlay fires `draw` once on layout before activate() (and never
	# activates on remote instances) — nothing to plot without a local player.
	if !_active:
		return
	for racer in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["Racers"]):
		# Ambient traffic isn't something you navigate by, and at 100+ riders plotting it
		# was most of this pass — and most of them pin to the map edge as arrows anyway.
		if racer.is_in_group(UtilsConstants.GROUPS["Traffic"]):
			continue
		var color := COLOR_PLAYER
		if racer == _local_player:
			color = COLOR_SELF
		elif racer is NPCRiderEntity:
			color = COLOR_NPC
		_draw_marker(racer.global_position, color)

	# Event start circles (local level nodes) — bright pink for testing.
	# Only in free roam; a race hides them so its checkpoint marker stands alone.
	if _local_player.gamemode_manager.current_game_mode == GameModeType.Kind.FREE_ROAM:
		for circle in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["EventCircles"]):
			_draw_marker(circle.global_position, COLOR_EVENT)

	if _has_checkpoint:
		_draw_marker(_checkpoint_pos, COLOR_CHECKPOINT)


## Plot a world position onto the overlay: clamp off-map points to the edge box
## with an outward pointer, then draw the bordered blip.
func _draw_marker(world_pos: Vector3, color: Color) -> void:
	var center := _dot_overlay.size * 0.5
	# Inset the clamp box so a pinned blip + border + arrow stays fully on-screen.
	var half := center - Vector2.ONE * (dot_radius + border_width + arrow_size)
	# unproject gives SubViewport pixels; the overlay is sized 1:1 over it.
	var pos := _camera.unproject_position(world_pos)
	var offset := pos - center
	if absf(offset.x) > half.x or absf(offset.y) > half.y:
		# Off-map: clamp onto the edge box along the ray from center, then
		# add an outward pointer toward the real position.
		var t := 1.0
		if absf(offset.x) > 0.001:
			t = minf(t, half.x / absf(offset.x))
		if absf(offset.y) > 0.001:
			t = minf(t, half.y / absf(offset.y))
		pos = center + offset * t
		_draw_edge_arrow(pos, offset.normalized(), color)
	_draw_blip(pos, color)


func _draw_blip(pos: Vector2, color: Color) -> void:
	_dot_overlay.draw_circle(pos, dot_radius + border_width, Color.BLACK)
	_dot_overlay.draw_circle(pos, dot_radius, color)


func _draw_edge_arrow(pos: Vector2, dir: Vector2, color: Color) -> void:
	var perp := Vector2(-dir.y, dir.x)
	var base := pos + dir * (dot_radius + border_width)
	var tip := base + dir * arrow_size
	_dot_overlay.draw_colored_polygon(
		PackedVector2Array([tip, base + perp * arrow_size, base - perp * arrow_size]), color
	)


## Server -> owning client: set (or clear) the local racer's next-checkpoint
## marker. Sent each frame while racing by the race gamemodes.
@rpc("authority", "call_local", "unreliable")
func rpc_set_checkpoint(pos: Vector3, has_target: bool) -> void:
	_checkpoint_pos = pos
	_has_checkpoint = has_target
