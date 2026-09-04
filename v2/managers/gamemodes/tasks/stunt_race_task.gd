@tool
## The stunt race's body task: point-to-point checkpoint racing plus the item-spawner lifecycle.
## Author the route as ONE ordered `checkpoints` list — cross them first-to-last, the last is the
## finish. Extends RaceTask to reuse its per-racer tracking / respawn-point / results / NPC support,
## but hides RaceTask's lap-shaped exports: the list drives start=first, end=last, middle=laps,
## total_laps=1. Use it in place of RaceTask under the SequentialTaskRunner.
##
## StuntRaceGameMode drives the spawners (on_race_start/on_race_end) so they're only live during
## the race. Spawner contract: activate() / deactivate() (GameModeObject provides both). Item
## spawners are TBD — see the item system in planning_docs/StuntRaceGamemode.md.
class_name StuntRaceTask extends RaceTask

## Route gates in order. Cross them first-to-last; the last one is the finish.
@export var checkpoints: Array[CheckPointMarker] = []
@export var spawners: Array[Node] = []


## Map the flat list onto RaceTask's start/lap/end before the base wires its signals (on_enter).
func on_enter(player: PlayerEntity, state: Dictionary) -> void:
	total_laps = 1
	start_checkpoint = checkpoints[0]
	end_checkpoint = checkpoints[checkpoints.size() - 1]
	lap_checkpoints = checkpoints.slice(1, checkpoints.size() - 1)
	super(player, state)


## Server-only, called by StuntRaceGameMode when the race starts.
func on_race_start() -> void:
	for spawner in spawners:
		spawner.activate()


## Server-only, called by StuntRaceGameMode when the race ends / the mode exits.
func on_race_end() -> void:
	for spawner in spawners:
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
	if checkpoints.size() < 2:
		issues.append("checkpoints needs at least 2 (start + finish)")
	return issues
