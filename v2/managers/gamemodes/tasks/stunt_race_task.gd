@tool
## The stunt race's body task: point-to-point checkpoint racing plus the item-spawner lifecycle.
## Author the route as the CheckPointMarker children of this task, in tree order — cross them
## first-to-last, the last is the finish (no StartStop marker). Extends RaceTask to reuse its
## route collection / per-racer tracking / respawn-point / results / NPC support, with
## total_laps fixed to 1. Use it in place of RaceTask under the SequentialTaskRunner.
##
## StuntRaceGameMode drives the spawners (on_race_start/on_race_end) so they're only live during
## the race. Spawner contract: activate() / deactivate() (GameModeObject provides both). Item
## spawners are TBD — see the item system in planning_docs/StuntRaceGamemode.md.
class_name StuntRaceTask extends RaceTask

## Signpost only (like RaceTask.first_checkpoint) — the live set is auto-collected from the
## PickupSpawner children (on_race_start).
@export var first_spawner: PickupSpawner


func _init():
	total_laps = 1


## Server-only, called by StuntRaceGameMode when the race starts. Spawners are
## the PickupSpawner children of this task — no manual inspector wiring.
func on_race_start() -> void:
	for spawner in find_children("*", "PickupSpawner", false):
		spawner.activate(_runner.spawn_manager)


## Server-only, called by StuntRaceGameMode when the race ends / the mode exits.
func on_race_end() -> void:
	for spawner in find_children("*", "PickupSpawner", false):
		spawner.deactivate()


## No laps here — show a plain running clock instead of RaceTask's "Lap x/y". The next gate is
## already pushed to the minimap by StuntRaceGameMode.
func _push_lap_hud(peer_id: int, p: Dictionary) -> void:
	var elapsed_ms: int = Time.get_ticks_msec() - p["start_ms"]
	var time_str := "%d:%05.2f" % [elapsed_ms / 60000, (elapsed_ms % 60000) / 1000.0]
	_runner.task_hud.rpc_update_progress.rpc_id(peer_id, time_str)


## Point-to-point, always one lap — hide RaceTask's total_laps.
func _validate_property(property: Dictionary) -> void:
	if property.name == "total_laps":
		property.usage = PROPERTY_USAGE_NO_EDITOR


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	var spawners := find_children("*", "PickupSpawner", false)
	if first_spawner == null:
		issues.append("assign first_spawner — PickupSpawner children are required (auto-collected at runtime)")
	elif not spawners.is_empty() and not spawners[0].name.ends_with("1"):
		issues.append("first PickupSpawner should be named ending in \"1\" so they count up")
	return issues
