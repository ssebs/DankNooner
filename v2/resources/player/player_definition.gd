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
		"bike_skin_res": bike_skin.resource_path,
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
	bike_skin = DictJSONSaverLoader.try_load(
		dict, "bike_skin_res", "res://resources/bikes/skins/sport_default_skin_definition.tres"
	)

#endregion
