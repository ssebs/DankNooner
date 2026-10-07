@tool
class_name SaveManager extends BaseManager

## The whole save was loaded or reset. Plain writes don't emit it — per-key changes come
## through save_item_updated (a PB save must not re-push player metadata mid-race).
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
	"version": save_version,
	"player_definition": default_player_definition,
	# TrickRow.pin ids shown on the riding HUD
	"pinned_tricks": [],
	# Earned per-player records. time_attack: "<level>/<event>" -> {best_lap_ms, best_run_ms}
	# owned: res paths of bought bike/character skins (see is_owned). Set by new-save seeding or
	# the pre-garage migration in load_save, so its absence marks an old save.
	"progression": {"time_attack": {}},
}

var current_save: Dictionary


func _ready():
	if Engine.is_editor_hint():
		return

	self.call_deferred("deferred_init")


func deferred_init():
	Console.add_command("give_money", _give_money, ["amount"], 1, "Add money to your profile")
	if FileAccess.file_exists(save_path):
		load_save()
	else:
		_save_default_save()


## New save: a private copy of default_player_definition (so edits don't leak into the shared
## .tres the NPC managers read), owning everything it uses.
func _seed_default_loadouts() -> void:
	var player_def := PlayerDefinition.new()
	player_def.from_dict(default_player_definition.to_dict())
	current_save["player_definition"] = player_def
	current_save["progression"]["owned"] = _referenced_skin_paths(player_def)
	save_save()


## res paths of every bike and character `player_def` uses.
func _referenced_skin_paths(player_def: PlayerDefinition) -> Array:
	var characters := SkinScanner.scan_skin_dir(PlayerDefinition.CHARACTER_SKINS_DIR)
	var paths := [characters[player_def.default_character.skin_name]]
	for loadout in player_def.loadouts:
		paths.append(loadout.bike.base_res_path)
		if loadout.character != null:
			paths.append(characters[loadout.character.skin_name])
	var unique := []
	for path in paths:
		if path not in unique:
			unique.append(path)
	return unique


## A skin is owned once bought, or if it's free.
func is_owned(path: String) -> bool:
	return load(path).price == 0 or path in current_save["progression"]["owned"]


## Spend `price` to own `path`. In memory only — the caller's next update_save writes it.
func purchase(path: String, price: int) -> bool:
	var player_def := get_player_definition()
	if player_def.money < price:
		return false
	player_def.money -= price
	current_save["progression"]["owned"].append(path)
	return true


## Take `amount` off the profile and write it. False, and nothing taken, if it's short.
## Doesn't emit save_item_updated — that re-pushes player metadata; HUDs poll money instead.
func spend(amount: int) -> bool:
	var player_def := get_player_definition()
	if player_def.money < amount:
		return false
	player_def.money -= amount
	save_save()
	return true


func _give_money(amount: String) -> void:
	var player_def := get_player_definition()
	player_def.money += amount.to_float()
	update_save("player_definition", player_def, true, true)
	Console.print_line("money: %d" % player_def.money)


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

	if !current_save["progression"].has("owned"):
		# Pre-garage save: keep everything it already uses.
		current_save["progression"]["owned"] = _referenced_skin_paths(current_save["player_definition"])
		needs_migration = true

	if needs_migration:
		save_save()  # persist migrated save
	save_changed.emit(current_save)


func get_player_definition() -> PlayerDefinition:
	return current_save["player_definition"]


## save_save() with default_save
func _save_default_save():
	load_default_save()
	_seed_default_loadouts()


## Load default_save to current_save
## emits save_changed
func load_default_save():
	# Deep copy so new-save seeding doesn't write into default_save's nested dicts.
	current_save = default_save.duplicate(true)
	save_changed.emit(current_save)
