@tool
## Heading strip top-centre of the riding HUD: N/E/S/W ticks plus the minimap's markers
## (Minimap.get_markers), spread across the camera's horizontal FOV. Pinned markers outside it
## sit at the ends with an outward arrow. Its backdrop is hud_scrim's top pool. Local and
## display-only.
class_name CompassStrip extends Control

@export var minimap: Minimap

const TICK_STEP_DEG: int = 15
const CARDINALS := {0: "N", 90: "E", 180: "S", 270: "W"}
const TICK_LEN: float = 6.0
const LETTER_COLOR := UtilsConstants.UI_BLUE
const NORTH_COLOR := UtilsConstants.UI_MAGENTA
## Line and ticks as a neon tube, bottom to top: [color, width, edge fade power]. The dark
## backing keeps it readable on any sky; the outer layers fade faster so the ends read thinner.
const TUBE_LAYERS := [
	[Color(UtilsConstants.UI_GLASS, 0.6), 6.0, 3.0],
	[UtilsConstants.UI_BLUE, 4.0, 2.0],
	[Color.WHITE, 1.5, 1.0],
]
## The tick line and ticks fade out over this many px at each end.
const EDGE_FADE_PX: float = 64.0
## Points per faded end; alpha follows a curve between them.
const FADE_STEPS: int = 12
const LETTER_FONT_SIZE: int = 16
## Room under the tick line for the cardinal letters.
const LETTER_BAND: float = 18.0
## Blip centres sit this far above the tick line.
const BLIP_LIFT: float = 20.0
## Editor preview faces north from the origin.
const PREVIEW_HALF_ARC_DEG: float = 50.0

var _local_player: PlayerEntity


func _ready():
	set_process(false)


## Called from RidingHUDState.show_ui, which only runs on the local client.
func activate(local_player: PlayerEntity) -> void:
	_local_player = local_player
	set_process(true)


func deactivate() -> void:
	_local_player = null
	set_process(false)
	queue_redraw()


func _process(_delta: float):
	queue_redraw()


func _draw():
	if Engine.is_editor_hint():
		_draw_strip(Vector2.UP, deg_to_rad(PREVIEW_HALF_ARC_DEG), Vector3.ZERO, _preview_markers())
		return
	# Draws on layout before activate() — nothing to plot without a rider.
	if _local_player == null:
		return
	var camera := get_viewport().get_camera_3d()
	# Adding cam-up keeps a horizontal heading even when the camera looks straight down.
	var cam_fwd := -camera.global_basis.z + camera.global_basis.y
	var fwd := Vector2(cam_fwd.x, cam_fwd.z)
	# Camera fov is vertical (KEEP_HEIGHT).
	var half_arc := atan(tan(deg_to_rad(camera.fov) * 0.5) * get_viewport_rect().size.aspect())
	_draw_strip(fwd, half_arc, _local_player.global_position, minimap.get_markers(false))


## fwd: camera heading on world XZ. half_arc: radians from centre to either end.
func _draw_strip(
	fwd: Vector2, half_arc: float, self_pos: Vector3, markers: Array[Dictionary]
) -> void:
	var line_y := size.y - LETTER_BAND

	for layer in TUBE_LAYERS:
		_draw_faded_line(line_y, layer[0], layer[1], layer[2])
	var font := get_theme_font("font", &"Label")
	for heading in range(0, 360, TICK_STEP_DEG):
		# World -Z is north, matching the full map.
		var dir := Vector2(sin(deg_to_rad(heading)), -cos(deg_to_rad(heading)))
		var angle := fwd.angle_to(dir)
		if absf(angle) > half_arc:
			continue
		var x := _x_for(angle, half_arc)
		if heading in CARDINALS:
			var text: String = CARDINALS[heading]
			var w := font.get_string_size(
				text, HORIZONTAL_ALIGNMENT_LEFT, -1, LETTER_FONT_SIZE
			).x
			var color := NORTH_COLOR if heading == 0 else LETTER_COLOR
			var baseline := Vector2(x - w * 0.5, size.y - 2.0)
			# Same dark outline as the HUD's labels.
			draw_string_outline(
				font,
				baseline,
				text,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				LETTER_FONT_SIZE,
				get_theme_constant("outline_size", &"Label"),
				get_theme_color("font_outline_color", &"Label")
			)
			draw_string(
				font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LETTER_FONT_SIZE, color
			)
		else:
			var tick_top := Vector2(x, line_y - TICK_LEN)
			var fade := clampf(minf(x, size.x - x) / EDGE_FADE_PX, 0.0, 1.0)
			for layer in TUBE_LAYERS:
				var color: Color = layer[0]
				draw_line(
					tick_top,
					Vector2(x, line_y),
					Color(color, color.a * pow(fade, layer[2])),
					layer[1],
					true
				)

	for m in markers:
		var to_marker := Vector2(m.pos.x - self_pos.x, m.pos.z - self_pos.z)
		var angle := fwd.angle_to(to_marker)
		var off_strip := absf(angle) > half_arc
		if off_strip and !m.pin:
			continue
		var radius := minimap.blip_radius(m.icon)
		var inset := radius + minimap.arrow_size
		var pos := Vector2(
			clampf(_x_for(clampf(angle, -half_arc, half_arc), half_arc), inset, size.x - inset),
			line_y - BLIP_LIFT
		)
		if off_strip:
			minimap.draw_edge_arrow(self, pos, Vector2(signf(angle), 0.0), radius, m.color)
		minimap.draw_blip(self, pos, m.color, m.icon)
		if m.name != "":
			minimap.draw_name_tag(self, m.name, pos)


## Full-width line across the strip; alpha ramps from 0 at each end as t^power over EDGE_FADE_PX.
func _draw_faded_line(y: float, color: Color, width: float, power: float) -> void:
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	for i in FADE_STEPS + 1:
		var t := float(i) / FADE_STEPS
		points.append(Vector2(t * EDGE_FADE_PX, y))
		colors.append(Color(color, color.a * pow(t, power)))
	for i in range(FADE_STEPS, -1, -1):
		var t := float(i) / FADE_STEPS
		points.append(Vector2(size.x - t * EDGE_FADE_PX, y))
		colors.append(Color(color, color.a * pow(t, power)))
	draw_polyline_colors(points, colors, width, true)


## Clockwise angle from camera-forward -> strip x; the strip's ends are the screen's edges.
func _x_for(angle: float, half_arc: float) -> float:
	return size.x * 0.5 * (1.0 + angle / half_arc)


## Sample markers for the editor preview: one of each kind, two off-strip.
func _preview_markers() -> Array[Dictionary]:
	return [
		Minimap.marker(Vector3(-30, 0, -100), Minimap.COLOR_PLAYER, null, true, "friend · 104m"),
		Minimap.marker(Vector3(60, 0, -80), Minimap.COLOR_NPC, null),
		Minimap.marker(Vector3(5, 0, -200), Minimap.COLOR_EVENT, Minimap.ICON_EVENT, false),
		Minimap.marker(Vector3(0, 0, 150), Minimap.COLOR_GAS_STATION, Minimap.ICON_GAS_STATION),
		Minimap.marker(Vector3(-200, 0, -60), Minimap.COLOR_CHECKPOINT, Minimap.ICON_CHECKPOINT),
	]
