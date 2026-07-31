## Lists the skin definitions sitting in a res:// folder. Lifted out of
## CustomizeMenuState so the customize menu and NPCTrafficManager enumerate skins
## the same way — anything with a `skin_name` counts, so bikes, characters and
## cars all list through here.
class_name SkinScanner extends RefCounted


## skin_name -> res:// path. Empty if the folder can't be opened.
static func scan_skin_dir(dir_path: String) -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		DebugUtils.DebugErrMsg("Failed to open skin directory: %s" % dir_path)
		return result

	# Exported builds ship .tres.remap names; the editor sees the .tres itself.
	var is_exported := !OS.has_feature("editor")
	var extension := ".tres.remap" if is_exported else ".tres"

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(extension):
			var res_path := dir_path + file_name.replace(".remap", "")
			var res := ResourceLoader.load(res_path)
			if res and "skin_name" in res:
				result[res.skin_name] = res_path
		file_name = dir.get_next()
	dir.list_dir_end()
	return result
