class_name DictJSONSaverLoader extends RefCounted


## Save json to file
static func save_json_to_file(path: String, dict: Dictionary) -> Error:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("failed to open %s" % path)
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
		printerr("failed to open %s" % path)
		return {}

	var json_dict = JSON.parse_string(file.get_as_text())
	if json_dict == null:
		printerr("failed to parse json from %s" % path)
		return {}
	file.close()

	return json_dict


#region (de)serializers
static func color_to_dict(c: Color) -> Dictionary:
	return {"r": c.r, "g": c.g, "b": c.b, "a": c.a}


static func dict_to_color(d: Dictionary) -> Color:
	if d.is_empty():
		return Color.TRANSPARENT
	return Color(d.get("r", 0.0), d.get("g", 0.0), d.get("b", 0.0), d.get("a", 1.0))


static func vec3_to_dict(v: Vector3) -> Dictionary:
	return {"x": v.x, "y": v.y, "z": v.z}


static func dict_to_vec3(d: Dictionary) -> Vector3:
	if d.is_empty():
		return Vector3.ZERO
	return Vector3(d.get("x", 0.0), d.get("y", 0.0), d.get("z", 0.0))
#endregion
