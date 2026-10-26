## Top-center HUD arrow pointing the local rider at the minimap's checkpoint target, relative to
## the camera, with the distance under it. While a guide target is on screen it pins over the
## target instead. Guide targets (drive to the start) always show it; race checkpoints only on easy.
## Local and display-only.
class_name TargetCompass extends Control

@export var minimap: Minimap

## Hidden this close to the target: the server registers a pass after the predicted rider has
## crossed, so the arrow would spin round as you go through.
const HIDE_WITHIN: float = 15.0

@onready var _distance: Label = %Distance

var _local_player: PlayerEntity
## Bearing to the target, clockwise from camera-forward.
var _angle: float = 0.0
## Whether the target is in view, and where it is in this control's space if so.
var _pinned: bool = false
var _pin_pos: Vector2


func _ready():
	hide()
	set_process(false)


## Called from RidingHUDState.show_ui, which only runs on the local client.
func activate(local_player: PlayerEntity) -> void:
	_local_player = local_player
	set_process(true)


func deactivate() -> void:
	_local_player = null
	set_process(false)
	hide()


func _process(_delta: float):
	var to_target := minimap.checkpoint_pos - _local_player.global_position
	var to_target_xz := Vector2(to_target.x, to_target.z)
	visible = (
		minimap.has_checkpoint
		and (minimap.checkpoint_is_guide or _is_easy())
		and to_target_xz.length() > HIDE_WITHIN
	)
	if !visible:
		return
	var camera := get_viewport().get_camera_3d()
	var screen_pos := camera.unproject_position(minimap.checkpoint_pos)
	_pinned = (
		minimap.checkpoint_is_guide
		and !camera.is_position_behind(minimap.checkpoint_pos)
		and get_viewport_rect().has_point(screen_pos)
	)
	if _pinned:
		_pin_pos = get_global_transform_with_canvas().affine_inverse() * screen_pos
	else:
		var fwd := -camera.global_basis.z
		# World XZ maps onto screen XY with -Z up, so a clockwise screen angle is a right turn.
		_angle = Vector2(fwd.x, fwd.z).angle_to(to_target_xz)
	_distance.text = tr("HUD_DISTANCE").format({"value": int(to_target_xz.length())})
	var below := _pin_pos if _pinned else Vector2(size.x * 0.5, size.y)
	_distance.position = below - Vector2(_distance.size.x * 0.5, 0)
	queue_redraw()


func _is_easy() -> bool:
	# 0 is easy, see SettingsManager.
	return _local_player.settings_manager.current_settings["difficulty"] == 0


func _draw():
	var r := minf(size.x, size.y) * 0.5
	if _pinned:
		# Flipped so the tip sits on the target.
		draw_set_transform(_pin_pos - Vector2(0, r), PI)
	else:
		draw_set_transform(size * 0.5, _angle)
	var points := PackedVector2Array(
		[Vector2(0, -r), Vector2(r * 0.7, r * 0.6), Vector2(0, r * 0.25), Vector2(-r * 0.7, r * 0.6)]
	)
	draw_colored_polygon(points, Minimap.COLOR_CHECKPOINT)
	points.append(points[0])
	draw_polyline(points, Color.BLACK, 2.0)
