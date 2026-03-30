@tool
class_name MainGame extends Node

@export var settings_manager: SettingsManager

@export_tool_button("Run Validation") var run_validation = _run_validation


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	settings_manager.all_settings_changed.connect(_on_all_settings_changed)
	settings_manager.setting_updated.connect(_on_setting_updated)

	print(tr("GAME_TITLE"))
	print(ProjectSettings.get_setting("application/config/version"))


func _on_all_settings_changed(new_settings: Dictionary):
	DisplayServer.window_set_mode(
		SettingsManager.str_to_windowmode(new_settings["fullscreen_mode"])
	)

	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	get_viewport().scaling_3d_scale = new_settings.get("resolution_scale", 1.0)
	print("VP scaling: %.2f" % get_viewport().scaling_3d_scale)


func _on_setting_updated(key: String, value: Variant):
	if key == "fullscreen_mode":
		DisplayServer.window_set_mode(SettingsManager.str_to_windowmode(value))


func _run_validation() -> void:
	var validator = load("res://utils/validation/auto_validator.gd")
	validator.validate_tree(get_tree())
	print("Validation complete!")
