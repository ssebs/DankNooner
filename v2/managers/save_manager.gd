@tool
class_name SaveManager extends BaseManager

signal save_changed(current_save: Dictionary)
signal save_item_updated(save_key: String, save_value: Variant)

@export var save_slot: int = 1
@export var save_version: int = 1
@export var default_player_definition: PlayerDefinition = load(
	"res://resources/entities/player/default_player_definition.tres"
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
	if FileAccess.file_exists(save_path):
		load_save()
	else:
		save_default_save()


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
		printerr("failed to parse json from %s" % save_path)
		return

	if json_dict["version"] != save_version:
		printerr("savegame.json version mismatch, %s != %s" % [json_dict["version"], save_version])
		# TODO: migrate version
		return

	for key in default_save.keys():
		if key == "player_definition":
			# Convert dict back to resource
			var player_def = PlayerDefinition.new()
			player_def.from_dict(json_dict.get("player_definition", default_player_definition))
			current_save["player_definition"] = player_def
		else:
			current_save[key] = json_dict.get(key, default_save[key])


## save_save() with default_save
func save_default_save():
	load_default_save()
	save_save()


## Load default_save to current_save
## emits save_changed
func load_default_save():
	current_save = default_save
	save_changed.emit(current_save)
