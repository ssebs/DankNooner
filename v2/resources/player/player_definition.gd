@tool
## All player objects should be defined from this
class_name PlayerDefinition extends Resource

@export var ui_icon: Texture = preload("res://resources/img/Logos/Logo.svg")
@export var username: String = "replace_me"
@export var money: float = 0.0

@export var character_skin: CharacterSkinDefinition = preload(
	"res://resources/player/skins/biker_default_skin_definition.tres"
)
@export var bike_skin: BikeSkinDefinition = preload(
	"res://resources/bikes/skins/sport_default_skin_definition.tres"
)


#region to/from Dictionary
func to_dict() -> Dictionary:
	return {
		"ui_icon_res": ui_icon.resource_path,
		"character_skin_res": character_skin.resource_path,
		"bike_skin_dict": bike_skin.to_dict(),
		"money": money,
		"username": username,
	}


func from_dict(dict: Dictionary):
	username = dict.get("username", "N/A")
	money = dict.get("money", 0.0)

	ui_icon = DictJSONSaverLoader.try_load(
		dict, "ui_icon_res", "res://resources/img/Logos/Logo.svg"
	)
	character_skin = DictJSONSaverLoader.try_load(
		dict,
		"character_skin_res",
		"res://resources/player/skins/biker_default_skin_definition.tres"
	)

	bike_skin = BikeSkinDefinition.new()
	var bd: Dictionary = dict.get("bike_skin_dict", {})
	if bd.is_empty():
		# Legacy save: bike_skin was a resource_path (often a stale user:// path).
		# Treat it as the base bike if it's a res:// path, else fall back to default.
		var legacy_path: String = dict.get("bike_skin_res", "")
		if not legacy_path.begins_with("res://"):
			legacy_path = "res://resources/bikes/skins/sport_default_skin_definition.tres"
		bd = {"base_res_path": legacy_path}
	bike_skin.from_dict(bd)

#endregion
