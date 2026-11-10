extends Node3D
## Marketing key-art studio. F6 plays a TrickDemo run over Stunt City, freezes it at freeze_time,
## places the moon next to the rider, then renders a master and crops every FORMATS entry around the
## rider with the logo stamped on, and quits. Writes out_dir/{full,simple}/<format>.png, plus
## contact_sheet.png: the Steam capsules at their real display sizes on Steam's background.
## "simple" drops the clouds and zooms in.
## Frame the shot by moving SubViewport/Camera3D; move the StuntCity instance to change the spot.
## Lighting: StuntCity's light is LIGHT_ONLY and MoonLight is SKY_ONLY, so placing the moon never
## backlights the rider; KeyLight / FillLight light him.

@export var bike_definition: BikeSkinDefinition
@export var bike_colors: ColorMod
@export var character_definition: CharacterSkinDefinition
## Per-slot overrides, TRANSPARENT skips (same as CharacterSkinDefinition.colors).
@export var character_colors: Array[Color] = []
@export var trick := TrickController.Trick.BACKFLIP
@export var trick_state := TrickController.TrickState.AIR
## Rider pose layered on the run (the backflip only rotates the bike), started POSE_LEAD before
## the freeze. NONE skips it.
@export var pose_trick := TrickController.Trick.HIGH_CHAIR
## Run time to freeze at. backflip: 2.19 is fully inverted near the apex, 2.1 is ~150° in.
@export var freeze_time: float = 2.1
## Bike centre above the rig origin, along the rig's up.
@export var subject_height: float = 0.7
## Rider bounding sphere around the bike centre, in metres. Crops scale this to each format.
@export var subject_radius: float = 1.0
## Wide so 3:1 crops can still sit the rider off-centre; tall crops only need its height.
@export var master_size := Vector2i(6144, 3072)
@export var glow_strength: float = 1.6
## night_sky.gdshader uniforms to override for the shoot (keep the Stunt City palette).
@export var sky_overrides: Dictionary = {}
## Moon position relative to the rider, in degrees of camera right / up.
@export var moon_offset_deg := Vector2(5, 7)
## One event prop kept in shot after the free-roam hide, e.g. a single arrow wall. Null = none.
@export var featured_prop: Node3D
@export var logo: Texture2D
@export_dir var out_dir: String = "res://resources/img/marketing/key_art"

const STEAM_BG := Color("1b2838")
## Preview renders at master_size / this; only captures pay for full res.
const PREVIEW_DIVISOR := 4
## Seconds before freeze_time to start pose_trick: long enough to settle into a held pose.
const POSE_LEAD := 0.8
const SIMPLE_ZOOM := 1.25
const SIMPLE_SKY := {"cloud_coverage_min": 0.0, "cloud_coverage_max": 0.0}
const SHADOW_SHRINK := 16
const SHADOW_PAD := 3
const SHADOW_OPACITY := 0.75
## Down-right, as a fraction of the logo's height.
const SHADOW_OFFSET := Vector2(0.03, 0.06)
## Border thickness as a fraction of the logo's height, drawn as BORDER_STEPS stamps around a ring.
const BORDER_WIDTH := 0.022
const BORDER_STEPS := 16
## Edge darkening: starts at VIGNETTE_START of the way to the edge midpoints, VIGNETTE_STRENGTH at
## the corners. Follows each format's aspect, since one small gradient is stretched to fit.
const VIGNETTE_START := 0.55
const VIGNETTE_STRENGTH := 0.6
## "sheet": contact-sheet sizes (Steam display sizes). "layout": logo_only centres the logo over the
## rider, centered centres the rider; "logo": false leaves it off.
const FORMATS := [
	{
		"name": "store_capsule_header",
		"size": Vector2i(920, 430),
		"sheet": [Vector2i(460, 215), Vector2i(184, 69), Vector2i(120, 45)],
	},
	{"name": "store_capsule_small", "size": Vector2i(462, 174), "sheet": [Vector2i(231, 87)], "layout": "logo_only"},
	{"name": "store_capsule_main", "size": Vector2i(1232, 706), "sheet": [Vector2i(616, 353)]},
	{"name": "store_capsule_vertical", "size": Vector2i(748, 896), "sheet": [Vector2i(374, 448)]},
	{"name": "library_capsule", "size": Vector2i(600, 900), "sheet": [Vector2i(300, 450)]},
	# Steam lays the library logo over the hero, so keep the rider clear of the sides.
	{"name": "library_hero", "size": Vector2i(3840, 1240), "logo": false, "layout": "centered"},
	{"name": "event_cover", "size": Vector2i(800, 450)},
	{"name": "event_header", "size": Vector2i(1920, 622)},
	{"name": "social_16x9", "size": Vector2i(1920, 1080)},
	{"name": "social_1x1", "size": Vector2i(1080, 1080)},
	{"name": "social_4x5", "size": Vector2i(1080, 1350)},
	{"name": "social_9x16", "size": Vector2i(1080, 1920)},
	{"name": "itch_cover", "size": Vector2i(630, 500)},
]

@onready var _viewport: SubViewport = %SubViewport
@onready var _camera: Camera3D = %Camera3D
@onready var _preview: TextureRect = %Preview
@onready var _env: WorldEnvironment = $StuntCity/WorldEnvironment
@onready var _demo: TrickDemo = $TrickDemoLevel/%TrickDemo
@onready var _anims: AnimationPlayer = $TrickDemoLevel/%DemoAnims
@onready var _rig: Node3D = $TrickDemoLevel/%Rig
@onready var _rider: RiderVisual = $TrickDemoLevel/%RiderVisual
@onready var _moon_light: DirectionalLight3D = %MoonLight

var _logo: Image
var _silhouette: Image
var _shadow: Image
var _vignette: Image
var _sky_mat: ShaderMaterial
## SIMPLE_SKY's uniforms as the full variant has them.
var _full_sky := {}
var _posed := false
var _frozen := false


func _ready() -> void:
	_logo = logo.get_image()
	_logo.decompress()
	_logo.convert(Image.FORMAT_RGBA8)
	_logo = _logo.get_region(_logo.get_used_rect())
	_silhouette = _logo.duplicate() as Image
	# Zero brightness blacks out RGB and keeps alpha.
	_silhouette.adjust_bcs(0.0, 1.0, 1.0)
	_shadow = _make_shadow(_silhouette)
	_vignette = _make_vignette()

	# Runtime edits of shared resources never reach disk, so the game's sky is safe.
	var env := _env.environment
	env.glow_strength = glow_strength
	_sky_mat = env.sky.sky_material as ShaderMaterial
	for uniform: String in sky_overrides:
		_sky_mat.set_shader_parameter(uniform, sky_overrides[uniform])
	for uniform: String in SIMPLE_SKY:
		_full_sky[uniform] = _sky_mat.get_shader_parameter(uniform)

	# What FreeRoamGameMode does on entry: event-only props (race walls, checkpoints) stay hidden.
	for circle in get_tree().get_nodes_in_group(UtilsConstants.GROUPS["EventCircles"]):
		(circle as EventStartCircle).set_active_event(null)
	if featured_prop != null:
		# Out from under its hidden event group; reparent keeps the global transform.
		featured_prop.reparent(self)

	_viewport.size = master_size / PREVIEW_DIVISOR
	_preview.texture = _viewport.get_texture()

	var bike := bike_definition.duplicate() as BikeSkinDefinition
	var mods: Array[BikeMod] = [bike_colors]
	bike.mods = mods
	var character := character_definition.duplicate() as CharacterSkinDefinition
	character.colors = character_colors
	_demo.show_rider(bike, character)
	_demo.play(trick, trick_state)


func _process(_delta: float) -> void:
	var t := _anims.current_animation_position
	if not _posed and t >= freeze_time - POSE_LEAD:
		_posed = true
		if pose_trick != TrickController.Trick.NONE:
			_rider.start_trick(pose_trick)
	if _frozen or t < freeze_time:
		return
	_anims.pause()
	_anims.seek(freeze_time, true)
	_frozen = true
	_capture()


func _capture() -> void:
	# Before unprojecting: pixel coords come from the viewport's current size.
	_viewport.size = master_size
	var center := _rig.global_position + _rig.global_basis.y * subject_height
	var cam_basis := _camera.global_basis
	var moon_dir := (center - _camera.global_position).normalized()
	moon_dir = moon_dir.rotated(cam_basis.y, deg_to_rad(-moon_offset_deg.x))
	moon_dir = moon_dir.rotated(cam_basis.x, deg_to_rad(moon_offset_deg.y))
	# Sky shaders put the moon along the light's +Z.
	_moon_light.global_basis = Basis.looking_at(-moon_dir)
	var center_px := _camera.unproject_position(center)
	var radius_px := center_px.distance_to(
		_camera.unproject_position(center + _camera.global_basis.y * subject_radius)
	)

	var shots := {}
	for variant: String in ["full", "simple"]:
		_set_sky(SIMPLE_SKY if variant == "simple" else _full_sky)
		# One frame to draw the change, one to read it back.
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var master := _viewport.get_texture().get_image()
		master.convert(Image.FORMAT_RGBA8)
		shots[variant] = _export_variant(variant, master, center_px, radius_px)

	var sheet_path := out_dir.path_join("contact_sheet.png")
	_contact_sheet(shots).save_png(ProjectSettings.globalize_path(sheet_path))
	DebugUtils.DebugMsg("Key art written to %s" % ProjectSettings.globalize_path(out_dir))
	get_tree().quit()


func _set_sky(uniforms: Dictionary) -> void:
	for uniform: String in uniforms:
		_sky_mat.set_shader_parameter(uniform, uniforms[uniform])


func _export_variant(variant: String, master: Image, center_px: Vector2, radius_px: float) -> Dictionary:
	var dir := ProjectSettings.globalize_path(out_dir.path_join(variant))
	DirAccess.make_dir_recursive_absolute(dir)
	master.save_png(dir.path_join("master.png"))
	var out := {}
	for format: Dictionary in FORMATS:
		var size: Vector2i = format.size
		var lay := _layout(size, format.get("layout", ""), variant == "simple")
		var rect := _crop_rect(Vector2(master.get_size()), center_px, radius_px, size, lay)
		var img := master.get_region(Rect2i(rect))
		img.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
		var vignette := _vignette.duplicate() as Image
		vignette.resize(size.x, size.y, Image.INTERPOLATE_CUBIC)
		img.blend_rect(vignette, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
		if format.get("logo", true):
			var logo_at: Vector2 = lay.logo_at
			# A clamped crop can push the rider onto the logo's side; swap sides so it never covers him.
			var subject_x := (center_px.x - rect.position.x) / rect.size.x
			if logo_at.x != 0.5 and (subject_x < 0.5) == (logo_at.x < 0.5):
				logo_at.x = 1.0 - logo_at.x
			_stamp_logo(img, logo_at, lay.logo_w)
		img.convert(Image.FORMAT_RGB8)
		img.save_png(dir.path_join(format.name + ".png"))
		out[format.name] = img
	return out


## Where the rider and logo sit, normalized: logo beside the rider on wide formats, above it on tall.
func _layout(size: Vector2i, layout: String, simple: bool) -> Dictionary:
	var aspect := float(size.x) / size.y
	var logo_aspect := float(_logo.get_width()) / _logo.get_height()
	var lay: Dictionary
	if layout == "logo_only":
		lay = {
			"subject_h": 0.9,
			"subject_at": Vector2(0.5, 0.5),
			"logo_at": Vector2(0.5, 0.5),
			"logo_w": 0.9 * size.x,
		}
	# Rider above centre in both, so the Stunt City skyline below him makes it into the crop.
	elif aspect >= 1.4:
		lay = {
			"subject_h": 0.62,
			"subject_at": Vector2(0.5 if layout == "centered" else 0.74, 0.45),
			"logo_at": Vector2(0.34, 0.42),
			"logo_w": minf(0.56 * size.x, 0.5 * size.y * logo_aspect),
		}
	else:
		lay = {
			"subject_h": 0.4,
			"subject_at": Vector2(0.5, 0.6),
			"logo_at": Vector2(0.5, 0.17),
			"logo_w": minf(0.88 * size.x, 0.26 * size.y * logo_aspect),
		}
	if simple:
		lay.subject_h *= SIMPLE_ZOOM
	return lay


## The master region for a format, clamped inside `bounds` (so the rider can end up off his mark).
func _crop_rect(bounds: Vector2, center_px: Vector2, radius_px: float, size: Vector2i, lay: Dictionary) -> Rect2:
	var aspect := float(size.x) / size.y
	# Shrink to fit the master if needed; the rider then just fills more of the frame.
	var crop_h := minf(2.0 * radius_px / lay.subject_h, minf(bounds.y, bounds.x / aspect))
	var crop_size := Vector2(crop_h * aspect, crop_h).floor()
	var subject_at: Vector2 = lay.subject_at
	var origin := (center_px - crop_size * subject_at).clamp(Vector2.ZERO, bounds - crop_size).floor()
	return Rect2(origin, crop_size)


## Soft drop shadow, then a black border (the silhouette stamped in a ring), then the logo.
func _stamp_logo(img: Image, at: Vector2, width: float) -> void:
	var size := Vector2i(roundi(width), roundi(width * _logo.get_height() / _logo.get_width()))
	var origin := Vector2i(Vector2(img.get_size()) * at) - size / 2

	var shadow_scale := width / (_shadow.get_width() - SHADOW_PAD * 2)
	var shadow := _shadow.duplicate() as Image
	shadow.resize(
		roundi(_shadow.get_width() * shadow_scale), roundi(_shadow.get_height() * shadow_scale), Image.INTERPOLATE_CUBIC
	)
	var shadow_at := origin - Vector2i.ONE * roundi(SHADOW_PAD * shadow_scale) + Vector2i(SHADOW_OFFSET * size.y)
	img.blend_rect(shadow, Rect2i(Vector2i.ZERO, shadow.get_size()), shadow_at)

	var border := _silhouette.duplicate() as Image
	border.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	for i in BORDER_STEPS:
		var offset := Vector2i(Vector2.from_angle(TAU * i / BORDER_STEPS) * BORDER_WIDTH * size.y)
		img.blend_rect(border, Rect2i(Vector2i.ZERO, size), origin + offset)

	var logo_img := _logo.duplicate() as Image
	logo_img.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	img.blend_rect(logo_img, Rect2i(Vector2i.ZERO, size), origin)


## Black logo silhouette, kept tiny: stretching it back up with cubic filtering is the blur.
func _make_shadow(silhouette: Image) -> Image:
	var small := silhouette.duplicate() as Image
	# Halving steps average neighbours; one big resize would just sample.
	while small.get_width() > silhouette.get_width() / SHADOW_SHRINK:
		small.resize(maxi(small.get_width() / 2, 1), maxi(small.get_height() / 2, 1), Image.INTERPOLATE_BILINEAR)
	var shadow := Image.create_empty(
		small.get_width() + SHADOW_PAD * 2, small.get_height() + SHADOW_PAD * 2, false, Image.FORMAT_RGBA8
	)
	for y in small.get_height():
		for x in small.get_width():
			shadow.set_pixel(x + SHADOW_PAD, y + SHADOW_PAD, Color(0, 0, 0, small.get_pixel(x, y).a * SHADOW_OPACITY))
	return shadow


## Small black radial gradient; stretched per format so its falloff stays smooth.
func _make_vignette() -> Image:
	const SIZE := 64
	var vignette := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var corner := Vector2.ONE.length()
	for y in SIZE:
		for x in SIZE:
			# -1..1 across the image, so the edge midpoints sit at 1 and the corners at sqrt(2).
			var dist := ((Vector2(x, y) + Vector2(0.5, 0.5)) / SIZE * 2.0 - Vector2.ONE).length()
			var alpha := smoothstep(VIGNETTE_START, corner, dist) * VIGNETTE_STRENGTH
			vignette.set_pixel(x, y, Color(0, 0, 0, alpha))
	return vignette


## One row per variant of every format's "sheet" sizes, on Steam's page background.
func _contact_sheet(shots: Dictionary) -> Image:
	const GAP := 24
	var rows: Array = []
	for variant: String in shots:
		var row: Array[Image] = []
		for format: Dictionary in FORMATS:
			for sheet_size: Vector2i in format.get("sheet", []):
				var thumb := (shots[variant][format.name] as Image).duplicate() as Image
				thumb.resize(sheet_size.x, sheet_size.y, Image.INTERPOLATE_LANCZOS)
				row.append(thumb)
		rows.append(row)

	var width := GAP
	var row_h := 0
	for thumb: Image in rows[0]:
		width += thumb.get_width() + GAP
		row_h = maxi(row_h, thumb.get_height())
	var sheet := Image.create_empty(width, GAP + rows.size() * (row_h + GAP), false, Image.FORMAT_RGB8)
	sheet.fill(STEAM_BG)
	var y := GAP
	for row: Array in rows:
		var x := GAP
		for thumb in row:
			sheet.blit_rect(thumb, Rect2i(Vector2i.ZERO, thumb.get_size()), Vector2i(x, y))
			x += thumb.get_width() + GAP
		y += row_h + GAP
	return sheet
