@tool
class_name WarmupMenuState extends MenuState
## Boot-time shader/pipeline warmup. Instances every level offscreen (with every skin and VFX
## inside it) and draws it for a few frames so Godot compiles its material/particle/shadow
## pipelines here — behind a "compiling shaders" screen — instead of hitching on first gameplay draw.
## The viewport has no environment or light of its own: shader variants depend on the level's
## fog/glow/lights, so each level must be drawn under exactly what it uses in-game.
## Runs once per build; Godot's own shader_cache persists the results across launches.

@export var level_manager: LevelManager
@export var next_state: MenuState  ## where to go once warmup finishes (splash)
## Frames drawn per level, so async (ubershader) pipeline compiles have time to settle.
@export var frames_per_level: int = 4
## PlayerEntity VFX scenes (exhaust flame, sparks). No level contains a player, so these
## are dropped into each level during its warmup, alongside every skin.
@export var vfx_scenes: Array[PackedScene] = []

const MARKER_PATH := "user://.shaders_warmed"

@onready var warmup_viewport: SubViewport = %WarmupViewport
@onready var warmup_camera: Camera3D = %WarmupCamera
## Mirrors the player's shadowed headlight so spot-light shader variants compile here too
@onready var warmup_spot_light: SpotLight3D = %WarmupSpotLight
@onready var progress_bar: ProgressBar = %ProgressBar


func Enter(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
	# Match the headlight, which has no shadow on web (PlayerEntity._ready)
	warmup_spot_light.shadow_enabled = not OS.has_feature("web")
	ui.show()
	# Time-to-here is pure Godot boot (engine init, main scene load, base-shader
	# compile) — everything before warmup starts. Compare against the warmup total.
	DebugUtils.DebugMsg("[warmup] UI shown %dms after boot" % Time.get_ticks_msec())

	if _cache_is_current():
		_finish()
		return

	# Paint the "compiling shaders" screen at 0% before the first (blocking) level
	# instantiate, so boot doesn't hang on a black frame then jump ahead.
	await RenderingServer.frame_post_draw
	var t_warm_start := Time.get_ticks_msec()
	await _warm_all_levels()
	DebugUtils.DebugMsg("[warmup] all levels warmed in %dms" % (Time.get_ticks_msec() - t_warm_start))
	# Overwrite the marker with this build's version (replaces any stale one).
	# Best-effort: a failed write (e.g. sandboxed web FS) just re-warms next launch.
	var f := FileAccess.open(MARKER_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(_current_version())
	_finish()


func Exit(_state_context: StateContext):
	ui.hide()


func _warm_all_levels() -> void:
	var levels: Array[PackedScene] = []
	for scene in level_manager.possible_levels.values():
		if scene != null and scene not in levels:
			levels.append(scene)
	# Every bike/character the customize menu offers — no level contains them
	var extras: Array[PackedScene] = vfx_scenes.duplicate()
	for skins_dir in [CustomizeMenuState.BIKE_SKINS_DIR, CustomizeMenuState.CHARACTER_SKINS_DIR]:
		for res_path in SkinScanner.scan_skin_dir(skins_dir).values():
			var skin_scene: PackedScene = load(res_path).mesh_res
			if skin_scene not in extras:
				extras.append(skin_scene)

	progress_bar.max_value = levels.size()
	progress_bar.value = 0

	for scene in levels:
		await _warm_level(scene, extras)
		progress_bar.value += 1
		# Repaint so the bar visibly climbs before the next blocking instantiate.
		await RenderingServer.frame_post_draw


## extras are placed in front of the camera so they draw under this level's environment/lights.
## They start hidden/idle (FlameMesh invisible, particles not emitting), so force them drawable —
## otherwise their pipelines never compile here.
func _warm_level(scene: PackedScene, extras: Array[PackedScene]) -> void:
	var t_start := Time.get_ticks_msec()
	var instance := scene.instantiate()
	warmup_viewport.add_child(instance)
	_frame_camera_to(instance)
	warmup_camera.make_current()
	var in_view := warmup_camera.global_position - warmup_camera.global_basis.z * 3.0
	for extra_scene in extras:
		var extra: Node3D = extra_scene.instantiate()
		instance.add_child(extra)
		extra.global_position = in_view
		_force_drawable(extra)
	# Skidmarks build their material at runtime (SkidmarkController._new_ribbon), so no scene carries it
	var skid_mat := ShaderMaterial.new()
	skid_mat.shader = SkidmarkController.SKID_SHADER
	skid_mat.set_shader_parameter("tex", SkidmarkController.SKID_TEXTURE)
	var skid := MeshInstance3D.new()
	skid.mesh = QuadMesh.new()
	skid.material_override = skid_mat
	skid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.add_child(skid)
	# QuadMesh faces +Z, the camera's back — so it faces the camera and isn't backface-culled
	skid.global_transform = Transform3D(warmup_camera.global_basis, in_view)
	var t_loaded := Time.get_ticks_msec()
	for _i in frames_per_level:
		await RenderingServer.frame_post_draw
	var t_rendered := Time.get_ticks_msec()
	instance.queue_free()
	# Let the freed instance leave the tree before the next add.
	await get_tree().process_frame
	var t_freed := Time.get_ticks_msec()
	DebugUtils.DebugMsg(
		"[warmup] %s: instantiate %dms, render %dms, free %dms" % [
			scene.resource_path.get_file(),
			t_loaded - t_start,
			t_rendered - t_loaded,
			t_freed - t_rendered
		]
	)


## Reveal every mesh and start every particle emitter so their materials actually draw.
func _force_drawable(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		mi.visible = true
	for p in root.find_children("*", "GPUParticles3D", true, false):
		p.emitting = true


## Aim the warmup camera at the instanced content's bounds so every mesh lands
## in-frustum and gets drawn (and thus compiled) at least once.
func _frame_camera_to(root: Node) -> void:
	var bounds := _combined_aabb(root)
	var center := bounds.get_center()
	var radius := maxf(bounds.size.length() * 0.5, 1.0)
	warmup_camera.global_position = center + Vector3(0, radius * 0.5, radius * 2.0)
	warmup_camera.look_at(center)
	warmup_camera.far = radius * 8.0
	warmup_spot_light.spot_range = warmup_camera.far


func _combined_aabb(node: Node) -> AABB:
	var result := AABB()
	var found := false
	for vi in node.find_children("*", "VisualInstance3D", true, false):
		var world_aabb: AABB = vi.global_transform * vi.get_aabb()
		if !found:
			result = world_aabb
			found = true
		else:
			result = result.merge(world_aabb)
	if !found:
		return AABB(Vector3.ZERO, Vector3.ONE)
	return result


## Cache is current only if the marker holds this exact build version; a mismatch
## (or missing marker) re-runs warmup, and the write above overwrites the old value.
func _cache_is_current() -> bool:
	# WebGL can't persist compiled shaders (Godot compiles the GLES3 cache out on web)
	if OS.has_feature("web"):
		return false
	if !FileAccess.file_exists(MARKER_PATH):
		return false
	var f := FileAccess.open(MARKER_PATH, FileAccess.READ)
	# Open failed despite existing → treat as stale and re-warm (safe fallback).
	if f == null:
		return false
	return f.get_as_text().strip_edges() == _current_version()


func _current_version() -> String:
	return ProjectSettings.get_setting("application/config/version", "dev")


func _finish() -> void:
	transitioned.emit(next_state, null)
