@tool
class_name CharacterSkinDefinition extends Resource

## Name of the skin for saving to disk
@export var skin_name: String = "replace_me"

## res:// path of the def this was copied from, so from_dict can rebuild it from the original.
## Empty for un-customized base defs (fall back to resource_path).
@export var base_res_path: String = ""

## The SkinColor scene to instantiate
@export var mesh_res: PackedScene:
	set(value):
		if value:
			var instance = value.instantiate()
			assert(instance is SkinColor, "Wrong scene type!")
			instance.free()
		mesh_res = value

## SkinSlot colors (use TRANSPARENT to skip a slot)
## See skin_color.gd
@export var colors: Array[Color] = []

## Garage cost; 0 = owned by default.
@export var price: int = 0

## Mesh is scaled so its AABB is this tall. Raise it when hair etc. inflates the AABB
@export var height: float = DEFAULT_HEIGHT

## Marker positions
@export_group("Markers")
@export var back_marker_position: Vector3 = Vector3.ZERO
@export var back_marker_rotation_degrees: Vector3 = Vector3.ZERO

const USER_SKIN_DIR: String = "user://skins/"
const SKIN_PFX: String = "character_skin_"
const DEFAULT_HEIGHT: float = 1.65


func save_to_disk():
	DirAccess.make_dir_recursive_absolute(USER_SKIN_DIR)
	var path = USER_SKIN_DIR + SKIN_PFX + skin_name.to_snake_case() + ".tres"
	var err = ResourceSaver.save(self, path)
	if err == OK:
		DebugUtils.DebugMsg("CharacterSkinDefinition: Saved to ", path)
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
	base_res_path = other.base_res_path
	mesh_res = other.mesh_res
	colors = other.colors.duplicate()
	price = other.price
	height = other.height
	back_marker_position = other.back_marker_position
	back_marker_rotation_degrees = other.back_marker_rotation_degrees


#region to/from Dictionary
## Only the base def's path + colors; everything else comes from the base def in from_dict().
func to_dict() -> Dictionary:
	var colors_arr: Array = []
	for c in colors:
		colors_arr.append(c.to_html())
	return {
		"base_res_path": base_res_path if base_res_path != "" else resource_path,
		"colors": colors_arr,
	}


func from_dict(dict: Dictionary):
	var base_path: String = dict.get("base_res_path", "")
	if !ResourceLoader.exists(base_path):
		base_path = PlayerDefinition.DEFAULT_CHARACTER_PATH
	_copy_from(load(base_path))
	base_res_path = base_path
	colors.clear()
	for hex in dict.get("colors", []):
		colors.append(Color.html(hex))
#endregion
