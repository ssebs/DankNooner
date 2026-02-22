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

const USER_SKIN_DIR: String = "user://skins/"
const SKIN_PFX: String = "character_skin_"


func save_to_disk():
	DirAccess.make_dir_recursive_absolute(USER_SKIN_DIR)
	var path = USER_SKIN_DIR + SKIN_PFX + skin_name.to_snake_case() + ".tres"
	var err = ResourceSaver.save(self, path)
	if err == OK:
		print("CharacterSkinDefinition: Saved to ", path)
	else:
		push_error("CharacterSkinDefinition: Failed to save, error: ", err)


## skin_name must be set before calling!
func load_from_disk() -> bool:
	var path = USER_SKIN_DIR + SKIN_PFX + skin_name.to_snake_case() + ".tres"
	if not ResourceLoader.exists(path):
		push_error("CharacterSkinDefinition: File not found: ", path)
		return false
	var loaded = ResourceLoader.load(path) as CharacterSkinDefinition
	if not loaded:
		push_error("CharacterSkinDefinition: Failed to load: ", path)
		return false
	_copy_from(loaded)
	return true


func _copy_from(other: CharacterSkinDefinition):
	skin_name = other.skin_name
	mesh_res = other.mesh_res
	primary_color = other.primary_color
	secondary_color = other.secondary_color
	back_marker_position = other.back_marker_position
	back_marker_rotation_degrees = other.back_marker_rotation_degrees


#region to/from Dictionary
func to_dict() -> Dictionary:
	return {
		"skin_name": skin_name,
		"mesh_res": mesh_res.resource_path,
		"primary_color": DictJSONSaverLoader.color_to_dict(primary_color),
		"secondary_color": DictJSONSaverLoader.color_to_dict(secondary_color),
		"back_marker_position": DictJSONSaverLoader.vec3_to_dict(back_marker_position),
		"back_marker_rotation_degrees":
		DictJSONSaverLoader.vec3_to_dict(back_marker_rotation_degrees)
	}


func from_dict(dict: Dictionary):
	skin_name = dict.get("skin_name", "failed_to_load")
	mesh_res = load(
		dict.get("mesh_res", "res://entities/player/characters/scenes/clanker_skin.tscn")
	)
	primary_color = DictJSONSaverLoader.dict_to_color(dict.get("primary_color", {}))
	secondary_color = DictJSONSaverLoader.dict_to_color(dict.get("secondary_color", {}))
	back_marker_position = DictJSONSaverLoader.dict_to_vec3(dict.get("back_marker_position", {}))
	back_marker_rotation_degrees = DictJSONSaverLoader.dict_to_vec3(
		dict.get("back_marker_rotation_degrees", {})
	)
#endregion
