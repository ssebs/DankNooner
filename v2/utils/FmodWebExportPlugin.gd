@tool
class_name FmodWebExportPlugin extends EditorExportPlugin

var _export_dir: String = ""
var _is_web: bool = false


func _get_name() -> String:
	return "FmodWebExport"


func _export_begin(features: PackedStringArray, _is_debug: bool, path: String, _flags: int) -> void:
	_is_web = features.has("web")
	# path is the full export path (e.g. "F:/...dist/dank-nooner-web/index.html")
	# but may also be res:// — globalize to be safe
	_export_dir = ProjectSettings.globalize_path(path).get_base_dir()
	DebugUtils.DebugMsg(
		(
			"FmodWebExportPlugin: _export_begin called, is_web=%s, path=%s, export_dir=%s"
			% [_is_web, path, _export_dir]
		)
	)
	DebugUtils.DebugMsg("FmodWebExportPlugin: features=%s" % [features])


func _export_end() -> void:
	DebugUtils.DebugMsg("FmodWebExportPlugin: _export_end called, is_web=%s" % _is_web)
	if not _is_web:
		return

	var banks_root: String = ProjectSettings.get_setting("Fmod/General/banks_path", "")
	if banks_root.is_empty():
		push_error("FmodWebExportPlugin: Fmod/General/banks_path not set")
		return

	var banks_root_abs := ProjectSettings.globalize_path(banks_root)
	var dir := DirAccess.open(banks_root_abs)
	if dir == null:
		push_error("FmodWebExportPlugin: Cannot open banks directory: %s" % banks_root_abs)
		return

	var banks_output_dir := _export_dir.path_join("banks")
	if not DirAccess.dir_exists_absolute(banks_output_dir):
		DirAccess.make_dir_absolute(banks_output_dir)

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".bank"):
			var src := banks_root_abs.path_join(file_name)
			var dst := banks_output_dir.path_join(file_name)
			var err := DirAccess.copy_absolute(src, dst)
			if err != OK:
				push_error(
					"FmodWebExportPlugin: Failed to copy %s -> %s (error %d)" % [src, dst, err]
				)
			else:
				DebugUtils.DebugMsg("FmodWebExportPlugin: Copied %s" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
