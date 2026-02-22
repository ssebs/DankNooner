@tool
class_name CharacterSkinDefinition extends Resource

## Name of the skin for saving to disk
@export var skin_name: String = "replace_me"

## The SkinColor scene to instantiate
@export var mesh_res: PackedScene:
	set(value):
		if value:
			var instance = value.instantiate()
			assert(instance is SkinColor, "Wrong scene type!")
			instance.free()
		mesh_res = value

## Primary color (use TRANSPARENT to skip)
@export var primary_color: Color = Color.TRANSPARENT

## Secondary color - only used if mesh has_secondary
@export var secondary_color: Color = Color.TRANSPARENT

## Marker positions
@export_group("Markers")
@export var back_marker_position: Vector3 = Vector3.ZERO
@export var back_marker_rotation_degrees: Vector3 = Vector3.ZERO

## ZZZ replaced with skin_name
const SAVE_PATH: String = "user://character_skin_ZZZ.json"
const SAVE_VERSION: int = 1


func save_to_disk():
	var json_dict = {
		"skin_name": skin_name,
		"mesh_res": mesh_res.resource_path,
		"primary_color": DictJSONSaverLoader.color_to_dict(primary_color),
		"secondary_color": DictJSONSaverLoader.color_to_dict(secondary_color),
		"back_marker_position": DictJSONSaverLoader.vec3_to_dict(back_marker_position),
		"back_marker_rotation_degrees":
		DictJSONSaverLoader.vec3_to_dict(back_marker_rotation_degrees)
	}
	var path = SAVE_PATH.replace("ZZZ", skin_name.to_snake_case())
	DictJSONSaverLoader.save_json_to_file(path, json_dict)


## skin_name must be set before calling!
func load_from_disk():
	var path = SAVE_PATH.replace("ZZZ", skin_name.to_snake_case())

	var json_dict = DictJSONSaverLoader.load_json_from_file(path)
	if json_dict == {}:
		printerr("failed to parse json from %s" % path)
		return

	skin_name = json_dict.get("skin_name", "failed_to_load")
	mesh_res = load(
		json_dict.get("mesh_res", "res://entities/player/characters/scenes/clanker_skin.tscn")
	)
	primary_color = DictJSONSaverLoader.dict_to_color(json_dict.get("primary_color", {}))
	secondary_color = DictJSONSaverLoader.dict_to_color(json_dict.get("secondary_color", {}))
	back_marker_position = DictJSONSaverLoader.dict_to_vec3(
		json_dict.get("back_marker_position", {})
	)
	back_marker_rotation_degrees = DictJSONSaverLoader.dict_to_vec3(
		json_dict.get("back_marker_rotation_degrees", {})
	)
