@tool
class_name WarmupMenuState extends MenuState
## Boot-time shader/pipeline warmup. Instances every level offscreen and draws it
## for a few frames so Godot compiles its material/particle/shadow pipelines here —
## behind a "compiling shaders" screen — instead of hitching on first gameplay draw.
## Runs once per build; Godot's own shader_cache persists the results across launches.

@export var level_manager: LevelManager
@export var next_state: MenuState  ## where to go once warmup finishes (splash)
## Frames drawn per level, so async (ubershader) pipeline compiles have time to settle.
@export var frames_per_level: int = 4

const MARKER_PATH := "user://.shaders_warmed"

@onready var warmup_viewport: SubViewport = %WarmupViewport
@onready var warmup_camera: Camera3D = %WarmupCamera
@onready var progress_bar: ProgressBar = %ProgressBar


func Enter(_state_context: StateContext):
	if Engine.is_editor_hint():
		return
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
	var scenes: Array[PackedScene] = []
	for scene in level_manager.possible_levels.values():
		if scene != null and scene not in scenes:
			scenes.append(scene)

	progress_bar.max_value = scenes.size()
	progress_bar.value = 0

	for scene in scenes:
		await _warm_scene(scene)
		progress_bar.value += 1
		# Repaint so the bar visibly climbs before the next blocking instantiate.
		await RenderingServer.frame_post_draw


func _warm_scene(scene: PackedScene) -> void:
	var t_start := Time.get_ticks_msec()
	var instance := scene.instantiate()
	warmup_viewport.add_child(instance)
	_frame_camera_to(instance)
	warmup_camera.make_current()
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


## Aim the warmup camera at the instanced content's bounds so every mesh lands
## in-frustum and gets drawn (and thus compiled) at least once.
func _frame_camera_to(root: Node) -> void:
	var bounds := _combined_aabb(root)
	var center := bounds.get_center()
	var radius := maxf(bounds.size.length() * 0.5, 1.0)
	warmup_camera.global_position = center + Vector3(0, radius * 0.5, radius * 2.0)
	warmup_camera.look_at(center)
	warmup_camera.far = radius * 8.0


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
