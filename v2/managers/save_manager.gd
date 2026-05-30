@tool
class_name SaveManager extends BaseManager

signal save_changed(current_save: Dictionary)
signal save_item_updated(save_key: String, save_value: Variant)

@export var save_slot: int = 1
@export var save_version: int = 1
@export var default_player_definition: PlayerDefinition = load(
	"res://resources/player/default_player_definition.tres"
)

var save_path: String:
	get:
		return "user://savegame_%d.json" % save_slot

## NOTE - key names (str) are hard coded in lots of places!
## if using a Definition, be sure to call to_dict/from_dict when save/loading it in the impl
var default_save: Dictionary = {
	"version": save_version, "player_definition": default_player_definition
}

var current_save: Dictionary


func _ready():
	if Engine.is_editor_hint():
		return

	self.call_deferred("deferred_init")


func deferred_init():
	var first_run := not FileAccess.file_exists(save_path)
	if first_run:
		_save_default_save()
	else:
		load_save()

	# First-run: seed one loadout per base bike found on disk.
	# Migration: existing save with no loadouts (legacy from_dict left it empty) → also seed.
	var player_def := get_player_definition()
	if first_run or player_def.loadouts.is_empty():
		_seed_default_loadouts(player_def)
		save_save()


const BIKE_SKINS_DIR := "res://resources/bikes/skins/"


## Scans res://resources/bikes/skins/ and creates one loadout per base bike found,
## with the skin's `skin_name` as the loadout name and no mods.
func _seed_default_loadouts(player_def: PlayerDefinition) -> void:
	var dir := DirAccess.open(BIKE_SKINS_DIR)
	if dir == null:
		DebugUtils.DebugErrMsg("SaveManager: failed to open %s" % BIKE_SKINS_DIR)
		return

	var is_exported := !OS.has_feature("editor")
	var extension := ".tres.remap" if is_exported else ".tres"

	var seeded: Array[BikeSkinDefinition] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(extension):
			var res_path := BIKE_SKINS_DIR + file_name.replace(".remap", "")
			var base := ResourceLoader.load(res_path) as BikeSkinDefinition
			if base != null:
				var loadout := BikeSkinDefinition.new()
				loadout.from_dict({"base_res_path": res_path, "skin_name": base.skin_name})
				seeded.append(loadout)
		file_name = dir.get_next()
	dir.list_dir_end()

	player_def.loadouts = seeded
	player_def.active_loadout_index = 0


# TODO - this may cause a dupe emit bug since save_settings also emits a signal
func update_save(
	key: String,
	value: Variant,
	should_emit_signal: bool = true,
	should_write_to_disk: bool = false,
):
	current_save[key] = value
	if should_write_to_disk:
		save_save()
	if should_emit_signal:
		save_item_updated.emit(key, value)


## write current_save to save_path
func save_save():
	var save_dict = current_save.duplicate()

	# Convert Resource to dict
	save_dict["player_definition"] = current_save["player_definition"].to_dict()

	DictJSONSaverLoader.save_json_to_file(save_path, save_dict)
	save_changed.emit(current_save)


## load save_path into current_save
## emits save_changed
func load_save():
	var json_dict = DictJSONSaverLoader.load_json_from_file(save_path)
	if json_dict == {}:
		DebugUtils.DebugErrMsg("failed to parse json from %s, resetting to defaults" % save_path)
		_save_default_save()
		return

	# old/missing version means an outdated save format — migrate by filling
	# any missing keys with defaults instead of discarding the file
	var needs_migration: bool = json_dict.get("version", -1) != save_version
	if needs_migration:
		DebugUtils.DebugErrMsg(
			"savegame.json version mismatch (%s != %s), filling missing keys with defaults"
			% [json_dict.get("version", "none"), save_version]
		)

	for key in default_save.keys():
		if key == "player_definition":
			# Convert dict back to resource
			var player_def = PlayerDefinition.new()
			player_def.from_dict(json_dict.get("player_definition", default_player_definition))
			current_save["player_definition"] = player_def
		else:
			current_save[key] = json_dict.get(key, default_save[key])
	current_save["version"] = save_version

	if needs_migration:
		save_save()  # persist migrated save


func get_player_definition() -> PlayerDefinition:
	return current_save["player_definition"]


## save_save() with default_save
func _save_default_save():
	load_default_save()
	save_save()


## Load default_save to current_save
## emits save_changed
func load_default_save():
	current_save = default_save
	save_changed.emit(current_save)
