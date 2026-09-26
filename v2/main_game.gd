@tool
class_name MainGame extends Node

@export var settings_manager: SettingsManager

@export_tool_button("Run Validation") var run_validation = _run_validation

## Mode last requested via window_set_mode, or -1. Size changes are ignored until the
## window reports it, so mid-transition modes (e.g. macOS fullscreen animation) aren't persisted.
var _pending_window_mode: int = -1


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	if OS.has_feature("web"):
		ProjectSettings.set_setting("netfox/time/tickrate", 20)

	settings_manager.all_settings_changed.connect(_on_all_settings_changed)
	settings_manager.setting_updated.connect(_on_setting_updated)

	get_window().size_changed.connect(_on_window_size_changed)

	DebugUtils.DebugMsg(tr("GAME_TITLE"))
	DebugUtils.DebugMsg(ProjectSettings.get_setting("application/config/version"))


## Alt+Enter flips between windowed and the fullscreen default. Goes through the
## setting rather than DisplayServer directly, so it persists and the settings
## menu shows the mode the window is actually in.
func _input(event: InputEvent):
	if !event.is_action_pressed("toggle_fullscreen"):
		return
	var is_windowed := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED
	var new_mode := "borderless" if is_windowed else "windowed"
	# save_settings emits all_settings_changed, which applies the window mode.
	settings_manager.update_setting("fullscreen_mode", new_mode, false)
	settings_manager.save_settings()


func _on_all_settings_changed(new_settings: Dictionary):
	_apply_window_mode(new_settings["fullscreen_mode"])

	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	get_viewport().scaling_3d_scale = new_settings.get("resolution_scale", 1.0)
	DebugUtils.DebugMsg("VP scaling: %.2f" % get_viewport().scaling_3d_scale)


func _on_setting_updated(key: String, value: Variant):
	if key == "fullscreen_mode":
		_apply_window_mode(value)


func _apply_window_mode(mode_str: String):
	var mode := SettingsManager.str_to_windowmode(mode_str)
	if DisplayServer.window_get_mode() == mode:
		return
	_pending_window_mode = mode
	DisplayServer.window_set_mode(mode)


# Persist window mode when the user changes it via the OS (e.g. clicking maximize)
func _on_window_size_changed():
	# Startup resizes fire before settings load (deferred_init); nothing to persist yet
	if settings_manager.current_settings.is_empty():
		return
	var current_mode := DisplayServer.window_get_mode()
	if _pending_window_mode != -1:
		if current_mode != _pending_window_mode:
			return
		_pending_window_mode = -1
	var current_mode_str := SettingsManager.windowmode_to_str(current_mode)
	if current_mode_str == "":
		return
	if settings_manager.current_settings.get("fullscreen_mode", "") == current_mode_str:
		return
	settings_manager.update_setting("fullscreen_mode", current_mode_str, false)
	settings_manager.save_settings()


func _run_validation() -> void:
	var validator = load("res://utils/validation/auto_validator.gd")
	validator.validate_tree(get_tree())
	DebugUtils.DebugMsg("Validation complete!")
