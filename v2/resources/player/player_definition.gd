@tool
## All player objects should be defined from this
class_name PlayerDefinition extends Resource

@export var ui_icon: Texture = preload("res://resources/img/Logos/Logo.svg")
@export var username: String = "replace_me"
@export var money: float = 0.0

## Rider for every loadout that doesn't pick its own.
@export var default_character: CharacterSkinDefinition = preload(DEFAULT_CHARACTER_PATH)

## `active_loadout_index` selects which one is currently in use.
@export var loadouts: Array[Loadout] = []
@export var active_loadout_index: int = 0

const MAX_LOADOUTS: int = 8
const DEFAULT_CHARACTER_PATH := "res://resources/player/skins/clanker_default_skin_definition.tres"
const CHARACTER_SKINS_DIR := "res://resources/player/skins/"
## Deleted character color variants -> [their base def, the variant's color].
const DELETED_CHARACTER_VARIANTS := {
	CHARACTER_SKINS_DIR + "biker_red_skin_definition.tres":
	[CHARACTER_SKINS_DIR + "biker_default_skin_definition.tres", Color(1, 0, 0, 1)],
	CHARACTER_SKINS_DIR + "biker_blue_skin_definition.tres":
	[CHARACTER_SKINS_DIR + "biker_default_skin_definition.tres", Color(0, 0, 1, 1)],
	CHARACTER_SKINS_DIR + "clanker_red_skin_definition.tres":
	[CHARACTER_SKINS_DIR + "clanker_default_skin_definition.tres", Color(1, 0.41, 0.41, 1)],
	CHARACTER_SKINS_DIR + "clanker_blue_skin_definition.tres":
	[CHARACTER_SKINS_DIR + "clanker_default_skin_definition.tres", Color(0.45, 0.5875, 1, 1)],
}

var bike_skin: BikeSkinDefinition:
	get:
		return loadouts[active_loadout_index].bike

var character_skin: CharacterSkinDefinition:
	get:
		var character := loadouts[active_loadout_index].character
		return character if character != null else default_character


#region to/from Dictionary
func to_dict() -> Dictionary:
	var loadout_dicts: Array = []
	for loadout in loadouts:
		loadout_dicts.append(loadout.to_dict())
	return {
		"ui_icon_res": ui_icon.resource_path,
		"default_character": default_character.to_dict(),
		"loadouts": loadout_dicts,
		"active_loadout_index": active_loadout_index,
		"money": money,
		"username": username,
	}


func from_dict(dict: Dictionary):
	username = dict.get("username", "N/A")
	money = dict.get("money", 0.0)

	ui_icon = DictJSONSaverLoader.try_load(
		dict, "ui_icon_res", "res://resources/img/Logos/Logo.svg"
	)
	default_character = CharacterSkinDefinition.new()
	if dict.has("default_character"):
		default_character.from_dict(dict["default_character"])
	else:
		# Legacy save: a path to a shared res:// def.
		_migrate_character_res(dict.get("character_skin_res", DEFAULT_CHARACTER_PATH))

	loadouts = [] as Array[Loadout]
	active_loadout_index = int(dict.get("active_loadout_index", 0))
	for loadout_dict: Dictionary in dict.get("loadouts", []):
		var loadout := Loadout.new()
		if loadout_dict.has("bike"):
			loadout.from_dict(loadout_dict)
		else:
			# Legacy save: each loadout was a bare bike dict.
			loadout.bike = BikeSkinDefinition.new()
			loadout.bike.from_dict(loadout_dict)
			loadout.name = loadout.bike.skin_name
		loadouts.append(loadout)

	if loadouts.is_empty():
		# Legacy save: single bike_skin_dict (or stale bike_skin_res path).
		var bd: Dictionary = dict.get("bike_skin_dict", {})
		if bd.is_empty():
			var legacy_path: String = dict.get("bike_skin_res", "")
			if not legacy_path.begins_with("res://"):
				legacy_path = "res://resources/bikes/skins/naked_default_skin_definition.tres"
			bd = {"base_res_path": legacy_path}
		var migrated := Loadout.new()
		migrated.bike = BikeSkinDefinition.new()
		migrated.bike.from_dict(bd)
		migrated.name = migrated.bike.skin_name
		loadouts = [migrated] as Array[Loadout]
		active_loadout_index = 0


## Copy `path` into default_character; deleted variants become their base + the variant's color.
func _migrate_character_res(path: String):
	if !DELETED_CHARACTER_VARIANTS.has(path) and !ResourceLoader.exists(path):
		path = DEFAULT_CHARACTER_PATH
	var variant: Array = DELETED_CHARACTER_VARIANTS.get(path, [path, null])
	default_character.from_dict((load(variant[0]) as CharacterSkinDefinition).to_dict())
	if variant[1] != null:
		default_character.colors = [variant[1]] as Array[Color]

#endregion
