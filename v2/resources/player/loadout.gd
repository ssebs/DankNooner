@tool
## A bike + rider pair on PlayerDefinition.loadouts. Hotkeys 1–8 swap between them.
class_name Loadout extends Resource

@export var name: String = ""
## Base bike + colors.
@export var bike: BikeSkinDefinition
## null = the profile's default_character.
@export var character: CharacterSkinDefinition


#region to/from Dictionary
func to_dict() -> Dictionary:
	return {
		"name": name,
		"bike": bike.to_dict(),
		"character": character.to_dict() if character != null else {},
	}


func from_dict(dict: Dictionary):
	name = dict.get("name", "")
	bike = BikeSkinDefinition.new()
	bike.from_dict(dict["bike"])
	var char_dict: Dictionary = dict.get("character", {})
	character = null
	if !char_dict.is_empty():
		character = CharacterSkinDefinition.new()
		character.from_dict(char_dict)
#endregion
