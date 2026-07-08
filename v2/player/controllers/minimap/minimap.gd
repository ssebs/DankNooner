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


func _process(_delta: float):
	if !_active:
		return

	# Look straight down at the player; player's forward becomes screen-up so the
	# map reads heading-up. Bike front is -Z (Godot convention, matches NPC rig).
	var player_fwd := -_local_player.global_transform.basis.z
	player_fwd.y = 0.0
	var cam_pos := _local_player.global_position + Vector3.UP * height
	_camera.look_at_from_position(cam_pos, _local_player.global_position, player_fwd)

	_dot_overlay.queue_redraw()


## Runs during the overlay's draw pass (connected to its `draw` signal), so the
## draw calls target the overlay canvas item on top of the SubViewport.
func _draw_dots() -> void:
	for racer in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["Racers"]):
		var color := COLOR_PLAYER
		if racer == _local_player:
			color = COLOR_SELF
		elif racer is NPCRiderEntity:
			color = COLOR_NPC
		_draw_marker(racer.global_position, color)

	# Event start circles (local level nodes) — bright pink for testing.
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
## marker. Sent each frame while racing by StreetRaceGameMode.
@rpc("authority", "call_local", "unreliable")
func rpc_set_checkpoint(pos: Vector3, has_target: bool) -> void:
	_checkpoint_pos = pos
	_has_checkpoint = has_target
