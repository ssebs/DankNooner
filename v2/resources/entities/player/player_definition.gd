@tool
## All player objects should be defined from this
class_name PlayerDefinition extends Resource

@export var ui_icon: Texture
@export var username: String
@export var money: int

@export var character_skin: CharacterSkinDefinition
@export var bike_skin: BikeSkinDefinition


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

	ui_icon = load(dict.get("ui_icon_res", "res://resources/img/Logos/Logo.svg"))
	character_skin = load(
		dict.get(
			"character_skin_res",
			"res://resources/entities/player/skins/biker_default_skin_definition.tres"
		)
	)
	bike_skin = load(
		dict.get(
			"bike_skin_res",
			"res://resources/entities/bikes/skins/sport_default_skin_definition.tres"
		)
	)

#endregion
