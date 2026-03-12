@tool
class_name SaveManager extends BaseManager

signal save_changed(current_save: Dictionary)
signal save_item_updated(save_key: String, save_value: Variant)

@export var save_path: String = "user://savegame01.json"
@export var save_version: int = 1
@export var player_definition: PlayerDefinition = load(
	"res://resources/entities/player/default_player_definition.tres"
)

## NOTE - key names (str) are hard coded in lots of places!
var default_save: Dictionary = {"version": save_version, "player_definition": player_definition}

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
	DictJSONSaverLoader.save_json_to_file(save_path, current_save)
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
