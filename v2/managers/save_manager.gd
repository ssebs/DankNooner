@tool
class_name SaveManager extends BaseManager

## The whole save was loaded or reset. Plain writes don't emit it — per-key changes come
## through save_item_updated (a PB save must not re-push player metadata mid-race).
signal save_changed(current_save: Dictionary)
signal save_item_updated(save_key: String, save_value: Variant)

## Bumping this retires every older save: it stays on disk, grayed out in the Saves menu, and
## boot starts a new save in a free slot (settings are a separate file).
## 2: bike unlock gates, so free-era saves don't keep bikes they never bought.
@export var save_version: int = 2
@export var default_player_definition: PlayerDefinition = load(
	"res://resources/player/default_player_definition.tres"
)
@export var steam_manager: SteamManager
## Holds the active slot (_slot_setting); loads before this manager.
@export var settings_manager: SettingsManager

## Progression keys each tutorial's milestones save under. Only the first gates the Play menu.
const TUTORIAL_KEY := "tutorial"
const ADVANCED_TUTORIAL_KEY := "tutorial_advanced"

## The active slot, read from settings in deferred_init.
var save_slot: int = 1

var save_path: String:
	get:
		return slot_path(save_slot)

## NOTE - key names (str) are hard coded in lots of places!
## if using a Definition, be sure to call to_dict/from_dict when save/loading it in the impl
var default_save: Dictionary = {
	"version": save_version,
	# Saves menu card name; blank shows "Save N"
	"name": "",
	"player_definition": default_player_definition,
	# TrickRow.pin ids shown on the riding HUD
	"pinned_tricks": [],
	# Earned per-player records. time_attack: "<level>/<event>" -> {best_lap_ms, best_run_ms}
	# owned: res paths of bought bike/character skins (see is_owned). Seeded on a new save.
	"progression": {"time_attack": {}},
}

var current_save: Dictionary

## settings.json key for the active slot, one per build like the save files.
var _slot_setting: String:
	get:
		return "demo_save_slot" if UtilsConstants.is_demo_build() else "save_slot"


func _ready():
	if Engine.is_editor_hint():
		return

	self.call_deferred("deferred_init")


func deferred_init():
	Console.add_command("dbg_set_money", _set_money, ["amount"], 1, "Set your profile's money")
	Console.add_command("dbg_set_level", _set_level, ["level"], 1, "Set your level, at its minimum XP")
	Console.add_command("dbg_skip_tutorial", mark_tutorial_complete, [], 0, "Mark the tutorial complete")
	Console.add_command("dbg_reset_tutorials", _reset_tutorials, [], 0, "Clear tour and tutorial progress")
	Console.add_command(
		"dbg_unlock_all", _unlock_all, [], 0, "Max money/XP, own all skins, skip tutorial, loadout per bike"
	)
	# JSON loads numbers as floats, hence the int().
	save_slot = int(settings_manager.current_settings[_slot_setting])
	_load_active()


## Demo saves get their own names, so neither build loads the other's (both share user://).
func slot_path(slot: int) -> String:
	return "user://savegame_%d%s.json" % [slot, "_demo" if UtilsConstants.is_demo_build() else ""]


## Slots with a save on disk for this build, ascending.
func saved_slots() -> Array[int]:
	var slots: Array[int] = []
	var slot_re := RegEx.create_from_string("^savegame_(\\d+)")
	for file in DirAccess.get_files_at("user://"):
		var found := slot_re.search(file)
		# The path check drops the other build's saves.
		if found != null and slot_path(int(found.get_string(1))) == "user://" + file:
			slots.append(int(found.get_string(1)))
	slots.sort()
	return slots


## The raw save in `slot`, {} if it's empty or won't parse.
func read_slot(slot: int) -> Dictionary:
	if !FileAccess.file_exists(slot_path(slot)):
		return {}
	return DictJSONSaverLoader.load_json_from_file(slot_path(slot))


## Older versions don't load; they only show (grayed out) in the Saves menu.
func is_current_version(save_dict: Dictionary) -> bool:
	return save_dict.get("version", -1) == save_version


## Make `slot` active and load it, starting a new save there if it's empty.
func switch_slot(slot: int) -> void:
	_set_slot(slot)
	_load_active()


## Deleting the active save moves to the lowest current-version save left, else a new save in
## the same slot.
func delete_slot(slot: int) -> void:
	DirAccess.remove_absolute(slot_path(slot))
	if slot != save_slot:
		return
	for other in saved_slots():
		if is_current_version(read_slot(other)):
			switch_slot(other)
			return
	switch_slot(slot)


func rename_slot(slot: int, slot_name: String) -> void:
	if slot == save_slot:
		current_save["name"] = slot_name
		save_save()
		return
	var save_dict := read_slot(slot)
	save_dict["name"] = slot_name
	DictJSONSaverLoader.save_json_to_file(slot_path(slot), save_dict)


func _set_slot(slot: int) -> void:
	save_slot = slot
	settings_manager.update_setting(_slot_setting, slot, false, true)


func _load_active() -> void:
	if FileAccess.file_exists(save_path):
		load_save()
	else:
		_save_default_save()
	_apply_steam_profile()


func _first_free_slot() -> int:
	var slot := 1
	while FileAccess.file_exists(slot_path(slot)):
		slot += 1
	return slot


## New save: a private copy of default_player_definition (so edits don't leak into the shared
## .tres the NPC managers read), owning everything it uses.
func _seed_default_loadouts() -> void:
	var player_def := PlayerDefinition.new()
	player_def.from_dict(default_player_definition.to_dict())
	current_save["player_definition"] = player_def
	current_save["progression"]["owned"] = _referenced_skin_paths(player_def)
	save_save()


## steam_id is per-session. The Steam name replaces the placeholder once; after that the
## username is the player's to change.
func _apply_steam_profile() -> void:
	var player_def := get_player_definition()
	var logged_in := steam_manager.is_logged_in()
	player_def.steam_id = steam_manager.steam.getSteamID() if logged_in else 0
	if !logged_in or player_def.username != default_player_definition.username:
		return
	player_def.username = steam_manager.steam.getPersonaName()
	update_save("player_definition", player_def, true, true)


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


## A bike skin is locked until the rider reaches its unlock_level, unless already owned.
func is_locked(path: String) -> bool:
	return !is_owned(path) and get_player_definition().level() < load(path).unlock_level


## Spend `price` to own `path`. In memory only — the caller's next update_save writes it.
func purchase(path: String, price: int) -> bool:
	var player_def := get_player_definition()
	if player_def.money < price:
		return false
	player_def.money -= price
	current_save["progression"]["owned"].append(path)
	return true


func is_tour_done(tour_id: StringName) -> bool:
	return String(tour_id) in current_save["progression"].get("tours_done", [])


func mark_tour_done(tour_id: StringName) -> void:
	var tours: Array = current_save["progression"].get_or_add("tours_done", [])
	if String(tour_id) not in tours:
		tours.append(String(tour_id))
	save_save()


func reset_tours() -> void:
	current_save["progression"]["tours_done"] = []
	save_save()


func _reset_tutorials() -> void:
	current_save["progression"].erase(TUTORIAL_KEY)
	current_save["progression"].erase(ADVANCED_TUTORIAL_KEY)
	reset_tours()
	Console.print_line("tours and tutorial reset")


## JSON loads numbers as floats, hence the int().
func get_tutorial_missions_done(key: String) -> int:
	return int(current_save["progression"].get(key, {}).get("missions_done", 0))


func set_tutorial_missions_done(key: String, count: int) -> void:
	current_save["progression"].get_or_add(key, {})["missions_done"] = count
	save_save()


func is_tutorial_complete() -> bool:
	return current_save["progression"].get(TUTORIAL_KEY, {}).get("complete", false)


func mark_tutorial_complete() -> void:
	current_save["progression"].get_or_add(TUTORIAL_KEY, {})["complete"] = true
	save_save()


## Take `amount` off the profile and write it. False, and nothing taken, if it's short.
## Doesn't emit save_item_updated — that re-pushes player metadata; HUDs poll money instead.
func spend(amount: int) -> bool:
	var player_def := get_player_definition()
	if player_def.money < amount:
		return false
	player_def.money -= amount
	save_save()
	return true


## Credit an event payout and write it. Like spend(), doesn't emit save_item_updated.
func earn(money: int, xp: int) -> void:
	var player_def := get_player_definition()
	player_def.money += money
	player_def.xp += xp
	save_save()


func _set_money(amount: String) -> void:
	var player_def := get_player_definition()
	player_def.money = amount.to_float()
	update_save("player_definition", player_def, true, true)
	Console.print_line("money: %d" % player_def.money)


## Inverse of PlayerDefinition.level().
func _set_level(level: String) -> void:
	var player_def := get_player_definition()
	player_def.xp = (level.to_int() - 1) ** 2 * UtilsConstants.XP_PER_LEVEL
	update_save("player_definition", player_def, true, true)
	Console.print_line("level: %d, xp: %d" % [player_def.level(), player_def.xp])


func _unlock_all() -> void:
	_set_money("1000000")
	_set_level("30")
	mark_tutorial_complete()
	var owned: Array = current_save["progression"]["owned"]
	for dir in [GarageUI.BIKE_SKINS_DIR, PlayerDefinition.CHARACTER_SKINS_DIR, HornDefinition.SKINS_DIR]:
		for path in SkinScanner.scan_skin_dir(dir).values():
			if path not in owned:
				owned.append(path)
	var player_def := get_player_definition()
	var loadout_bikes := player_def.loadouts.map(func(l: Loadout): return l.bike.base_res_path)
	for path in SkinScanner.scan_skin_dir(GarageUI.BIKE_SKINS_DIR).values():
		if path in loadout_bikes or player_def.loadouts.size() >= PlayerDefinition.MAX_LOADOUTS:
			continue
		var loadout := Loadout.new()
		loadout.from_dict({"bike": {"base_res_path": path}})
		loadout.name = loadout.bike.skin_name
		player_def.loadouts.append(loadout)
	update_save("player_definition", player_def, true, true)
	Console.print_line("unlocked all, %d loadouts" % player_def.loadouts.size())


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

	if !is_current_version(json_dict):
		DebugUtils.DebugErrMsg(
			"%s is version %s, not %s: keeping it, starting a new save in a free slot"
			% [save_path, json_dict.get("version", "none"), save_version]
		)
		_set_slot(_first_free_slot())
		_save_default_save()
		return

	for key in default_save.keys():
		if key == "player_definition":
			# Convert dict back to resource
			var player_def = PlayerDefinition.new()
			player_def.from_dict(json_dict.get("player_definition", default_player_definition))
			current_save["player_definition"] = player_def
		else:
			current_save[key] = json_dict.get(key, default_save[key])
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
