@tool
## All player objects should be defined from this
class_name PlayerDefinition extends Resource

@export var ui_icon: Texture = preload("res://resources/img/Logos/Logo.svg")
@export var username: String = "replace_me"
@export var money: float = 0.0

@export var character_skin: CharacterSkinDefinition = preload(
	"res://resources/player/skins/clanker_blue_skin_definition.tres"
)

## Named bike loadouts. Each entry is a BikeSkinDefinition (base bike + mods).
## `active_loadout_index` selects which one is currently in use.
@export var loadouts: Array[BikeSkinDefinition] = []
@export var active_loadout_index: int = 0

const MAX_LOADOUTS: int = 8

## Backwards-compatible accessor: reads/writes the active loadout slot. The setter will
## seed `loadouts[0]` if the array is empty (e.g. .tres deserialization).
var bike_skin: BikeSkinDefinition:
	get:
		if loadouts.is_empty():
			return null
		var idx := clampi(active_loadout_index, 0, loadouts.size() - 1)
		return loadouts[idx]
	set(value):
		if loadouts.is_empty():
			loadouts = [value] as Array[BikeSkinDefinition]
			active_loadout_index = 0
		else:
			var idx := clampi(active_loadout_index, 0, loadouts.size() - 1)
			loadouts[idx] = value


#region to/from Dictionary
func to_dict() -> Dictionary:
	var loadout_dicts: Array = []
	for ld in loadouts:
		if ld != null:
			loadout_dicts.append(ld.to_dict())
	return {
		"ui_icon_res": ui_icon.resource_path,
		"character_skin_res": character_skin.resource_path,
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
	character_skin = DictJSONSaverLoader.try_load(
		dict, "character_skin_res", "res://resources/player/skins/clanker_blue_skin_definition.tres"
	)

	loadouts = [] as Array[BikeSkinDefinition]
	var loadout_dicts: Array = dict.get("loadouts", [])
	if not loadout_dicts.is_empty():
		for ld_dict in loadout_dicts:
			var ld := BikeSkinDefinition.new()
			ld.from_dict(ld_dict)
			loadouts.append(ld)
		active_loadout_index = dict.get("active_loadout_index", 0)
	else:
		# Legacy save: single bike_skin_dict (or stale bike_skin_res path).
		var bd: Dictionary = dict.get("bike_skin_dict", {})
		if bd.is_empty():
			var legacy_path: String = dict.get("bike_skin_res", "")
			if not legacy_path.begins_with("res://"):
				legacy_path = "res://resources/bikes/skins/naked_default_skin_definition.tres"
			bd = {"base_res_path": legacy_path}
		var migrated := BikeSkinDefinition.new()
		migrated.from_dict(bd)
		loadouts = [migrated] as Array[BikeSkinDefinition]
		active_loadout_index = 0

#endregion
