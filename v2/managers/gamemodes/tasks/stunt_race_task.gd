@tool
## The stunt race's body task: point-to-point checkpoint racing plus the item-spawner lifecycle.
## Author the route as the CheckPointMarker children of this task, in tree order — cross them
## first-to-last, the last is the finish. Extends RaceTask to reuse its per-racer tracking /
## respawn-point / results / NPC support,
## but hides RaceTask's lap-shaped exports: the list drives start=first, end=last, middle=laps,
## total_laps=1. Use it in place of RaceTask under the SequentialTaskRunner.
##
## StuntRaceGameMode drives the spawners (on_race_start/on_race_end) so they're only live during
## the race. Spawner contract: activate() / deactivate() (GameModeObject provides both). Item
## spawners are TBD — see the item system in planning_docs/StuntRaceGamemode.md.
class_name StuntRaceTask extends RaceTask

## Signposts only — assign the first of each so a fresh node shows in the inspector that these
## children are expected. The live sets are auto-collected from the children (on_enter/on_race_start).
@export var first_checkpoint: CheckPointMarker
@export var first_spawner: PickupSpawner


## Map the CheckPointMarker children onto RaceTask's start/lap/end before the base wires its
## signals (on_enter).
func on_enter(player: PlayerEntity, state: Dictionary) -> void:
	var checkpoints: Array[CheckPointMarker] = []
	checkpoints.assign(find_children("*", "CheckPointMarker", false))
	total_laps = 1
	start_checkpoint = checkpoints[0]
	end_checkpoint = checkpoints[checkpoints.size() - 1]
	lap_checkpoints = checkpoints.slice(1, checkpoints.size() - 1)
	super(player, state)


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


## Hide RaceTask's lap-shaped exports — the single `checkpoints` list drives them.
func _validate_property(property: Dictionary) -> void:
	if property.name in ["start_checkpoint", "lap_checkpoints", "end_checkpoint", "total_laps"]:
		property.usage = PROPERTY_USAGE_NO_EDITOR


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	var checkpoints := find_children("*", "CheckPointMarker", false)
	if first_checkpoint == null:
		issues.append("assign first_checkpoint — CheckPointMarker children are required (auto-collected at runtime)")
	elif checkpoints.size() < 2:
		issues.append("needs at least 2 CheckPointMarker children (start + finish)")
	elif not checkpoints[0].name.ends_with("1"):
		issues.append("first CheckPointMarker should be named ending in \"1\" so route order counts up")
	var spawners := find_children("*", "PickupSpawner", false)
	if first_spawner == null:
		issues.append("assign first_spawner — PickupSpawner children are required (auto-collected at runtime)")
	elif not spawners.is_empty() and not spawners[0].name.ends_with("1"):
		issues.append("first PickupSpawner should be named ending in \"1\" so they count up")
	return issues
