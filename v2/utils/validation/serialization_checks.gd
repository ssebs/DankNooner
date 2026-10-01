## Serialization round-trip checks: to_dict -> from_dict -> to_dict must give back the same dict.
##
## Each case runs both ways a dict travels: raw over RPC, and through JSON text for save files
## (JSON turns ints into floats, so a field missing its type coercion shows up here).
##
## Usage: main_game.gd _run_validation() loads this and calls run() after AutoValidator (debug only)

## BikeSkinDefinition.from_dict caches itself to user://skins/ under its skin_name. A fixture name
## keeps the checks from overwriting a player's real saved skin; the file is deleted afterwards.
const FIXTURE_SKIN_NAME := "validator_fixture"
const FIXTURE_BASE := "res://resources/bikes/skins/naked_default_skin_definition.tres"
const FIXTURE_MOD := "res://resources/bikes/mods/color_mods/black_blue_color.tres"


static func run() -> void:
	if not OS.is_debug_build():
		return

	var errors: Array[String] = []
	errors.append_array(_check_player_definition())
	errors.append_array(_check_legacy_save_migration())
	errors.append_array(_check_results_data())
	DirAccess.remove_absolute(_fixture_bike().get_user_save_path())

	for error in errors:
		push_error("SerializationChecks: %s" % error)

	if not errors.is_empty():
		assert(false, "SerializationChecks failed with %d error(s)" % errors.size())


## Lobby/spawn RPCs and savegame.json.
static func _check_player_definition() -> Array[String]:
	var player := PlayerDefinition.new()
	player.username = "validator"
	player.money = 12.5
	player.loadouts = [_fixture_bike(), _fixture_bike()] as Array[BikeSkinDefinition]
	player.active_loadout_index = 1

	var rebuild := func(d: Dictionary) -> Dictionary:
		var rebuilt := PlayerDefinition.new()
		rebuilt.from_dict(d)
		return rebuilt.to_dict()
	return _round_trip("PlayerDefinition", player.to_dict(), rebuild, true)


## SaveManager.load_save feeds pre-loadout saves (single bike_skin_dict) through from_dict.
## The bike_skin_res legacy branch isn't covered: it caches under the base bike's own skin_name.
static func _check_legacy_save_migration() -> Array[String]:
	var player := PlayerDefinition.new()
	player.from_dict(
		{
			"username": "validator",
			"bike_skin_dict": {"base_res_path": FIXTURE_BASE, "skin_name": FIXTURE_SKIN_NAME},
		}
	)
	if player.loadouts.size() != 1 or player.bike_skin.base_res_path != FIXTURE_BASE:
		return ["legacy bike_skin_dict save didn't migrate into a single loadout"]
	return []


## Results screen RPCs only — never saved, so no JSON pass.
static func _check_results_data() -> Array[String]:
	var rows: Array[Dictionary] = [
		{"Username": "a", "Time": "0:42.10"}, {"Username": "b", "Time": "DNF"}
	]
	var data := ResultsData.create("validator", ["Username", "Time"], rows, ["", "⏱"])
	var rebuild := func(d: Dictionary) -> Dictionary: return ResultsData.from_dict(d).to_dict()
	return _round_trip("ResultsData", data.to_dict(), rebuild, false)


## Feeds `original` to `rebuild` (from_dict then to_dict) raw, and through JSON text if `via_json`.
static func _round_trip(
	label: String, original: Dictionary, rebuild: Callable, via_json: bool
) -> Array[String]:
	var errors: Array[String] = []
	var inputs := {"rpc": original.duplicate(true)}
	if via_json:
		inputs["json"] = JSON.parse_string(JSON.stringify(original))
	for path in inputs:
		var rebuilt: Dictionary = rebuild.call(inputs[path])
		if rebuilt != original:
			errors.append(
				"%s (%s) round-trip mismatch:\n  before %s\n  after  %s"
				% [label, path, original, rebuilt]
			)
	return errors


static func _fixture_bike() -> BikeSkinDefinition:
	var bike := BikeSkinDefinition.new()
	bike.from_dict(
		{"skin_name": FIXTURE_SKIN_NAME, "base_res_path": FIXTURE_BASE, "mod_paths": [FIXTURE_MOD]}
	)
	return bike
