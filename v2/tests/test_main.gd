extends Node
## Boots main_game on per-peer test save/settings files, then hands off to the TestRunner.
## Launched by tests/run.py — see planning_docs/Testing.md.

const ErrorLogger := preload("res://tests/error_logger.gd")
const TestRunner := preload("res://tests/test_runner.gd")
const MAIN_GAME_SCENE := preload("res://main_game.tscn")
## Far from real slots, so a run never touches the player's save
const SAVE_SLOT_BASE := 100

@onready var test_runner: TestRunner = %TestRunner


func _ready() -> void:
	var logger := ErrorLogger.new()
	OS.add_logger(logger)
	var args := _parse_args()
	var main_game := MAIN_GAME_SCENE.instantiate() as MainGame
	_use_test_files(main_game, args["peer"])
	add_child(main_game)
	test_runner.run(logger, args)


## `--peer N --peers N --late-join 0|1 --out DIR`, as run.py passes them
func _parse_args() -> Dictionary:
	var raw := OS.get_cmdline_user_args()
	var flags := {}
	for i in range(0, raw.size(), 2):
		flags[raw[i].trim_prefix("--")] = raw[i + 1]
	return {
		"peer": int(flags["peer"]),
		"peers": int(flags["peers"]),
		"late_join": flags["late-join"] == "1",
		"out": flags["out"],
	}


## Both managers load in deferred_init, so this runs before they read anything.
func _use_test_files(main_game: MainGame, peer: int) -> void:
	var settings_manager := main_game.settings_manager
	settings_manager.settings_path = "user://test_settings_%d.json" % peer
	# The project boots maximized; switching to windowed lands on run.py's --position/--resolution
	# SaveManager reads its slot from settings (save_slot; the test build isn't the demo).
	DictJSONSaverLoader.save_json_to_file(
		settings_manager.settings_path,
		{
			"version": settings_manager.settings_version,
			"fullscreen_mode": "windowed",
			"save_slot": SAVE_SLOT_BASE + peer,
		}
	)
	for manager in settings_manager.get_parent().get_children():
		if manager is SaveManager:
			DirAccess.remove_absolute(manager.slot_path(SAVE_SLOT_BASE + peer))  # fresh save every run
			# A fresh save gates the Play menu behind the tutorial. Deferred past deferred_init's seeding.
			manager.save_changed.connect(
				manager.mark_tutorial_complete.unbind(1), CONNECT_DEFERRED | CONNECT_ONE_SHOT
			)
		elif manager is TourManager:
			manager.dbg_disable_tours = true
