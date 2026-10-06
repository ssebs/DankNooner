class_name DictJSONSaverLoader extends RefCounted


## Save json to file
static func save_json_to_file(path: String, dict: Dictionary) -> Error:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		DebugUtils.DebugErrMsg("failed to open %s" % path)
		return ERR_FILE_CANT_OPEN

	var json_str = JSON.stringify(dict)
	var ok = file.store_string(json_str)
	file.close()
	if !ok:
		return ERR_FILE_CANT_WRITE
	print("saved %s" % path)
	return OK


## Returns {} if there's an err
static func load_json_from_file(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		DebugUtils.DebugErrMsg("failed to open %s" % path)
		return {}

	var json_dict = JSON.parse_string(file.get_as_text())
	if json_dict == null:
		DebugUtils.DebugErrMsg("failed to parse json from %s" % path)
		return {}
	file.close()

	return json_dict


#region (de)serializers
## Try to load a resource path from dict[dict_key], fall back to default_path on failure
static func try_load(dict: Dictionary, dict_key: String, default_path: String) -> Resource:
	var loaded = load(dict.get(dict_key, ""))
	return loaded if loaded else load(default_path)
#endregion
