@tool
## Riders knocked out (ram, oil slick, shotgun — see SpawnManager.knock_out), frozen at the finish line.
class_name KnockoutScoringComponent extends RaceComponent

@export var points_per_knockout: int = 100

## peer_id -> knockouts credited this race.
var _knockouts: Dictionary[int, int] = {}
## Finished racers — knockouts after the line don't count.
var _finished: Dictionary[int, bool] = {}


func race_start() -> void:
	_knockouts.clear()
	_finished.clear()
	race_mode.spawn_manager.player_knocked_out.connect(_on_player_knocked_out)


func racer_finished(peer_id: int) -> void:
	_finished[peer_id] = true


func race_end() -> void:
	race_mode.spawn_manager.player_knocked_out.disconnect(_on_player_knocked_out)


func score(peer_id: int) -> float:
	return _knockouts.get(peer_id, 0) * points_per_knockout


func column_headers() -> PackedStringArray:
	return PackedStringArray(["💥 %s" % tr("LB_KNOCKOUTS")])


func column_cells(peer_id: int) -> PackedStringArray:
	return PackedStringArray(["%d" % _knockouts.get(peer_id, 0)])


func _on_player_knocked_out(_victim_peer_id: int, aggressor_peer_id: int) -> void:
	if _finished.has(aggressor_peer_id):
		return
	_knockouts[aggressor_peer_id] = _knockouts.get(aggressor_peer_id, 0) + 1
