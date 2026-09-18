@tool
## Base for a passive, whole-race side-challenge (e.g. longest wheelie). Server-only:
## the gamemode ticks it each frame from synced player state, then broadcasts the leader
## and each player's own best to the HUD. Assign a subclass .tres to
## StuntRaceGameMode.race_challenge. See planning_docs/StuntRaceGamemode.md.
class_name RaceChallenge extends Resource

## peer_id -> best value this race. Units are subclass-defined (see format_value).
## Runtime state; reset() owns its lifecycle so the authored .tres carries no stale data.
var _best: Dictionary[int, float] = {}


## Wipe all state and seed the given peers at zero. Called on race start/restart.
func reset(peer_ids: Array) -> void:
	_best.clear()
	for peer_id in peer_ids:
		_best[peer_id] = 0.0


## Accumulate one peer's state for this frame. Override in the subclass.
func tick(_peer_id: int, _player: PlayerEntity, _delta: float) -> void:
	pass


func get_best(peer_id: int) -> float:
	return _best.get(peer_id, 0.0)


## Human-readable value, e.g. "4.2s". Override in the subclass.
func format_value(_value: float) -> String:
	return ""


## Localized challenge name for the HUD/results. Override in the subclass.
func title() -> String:
	return ""
