@tool
extends Node

@export_tool_button("Take screenshot") var b = _take_screenshot


func _take_screenshot():
	var path: String = "res://resources/img/level_previews/Screenshot_RenameMe.jpg"

	var viewport = EditorInterface.get_editor_viewport_3d(0)
	var img = viewport.get_texture().get_image()
	img.save_jpg(path)

	print("Saved screenshot to %s" % path)

	OS.shell_show_in_file_manager(ProjectSettings.globalize_path(path))
