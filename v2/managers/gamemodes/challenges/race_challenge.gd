@tool
## Base for a passive, whole-race side-challenge (e.g. longest wheelie). Server-only:
## the gamemode ticks it each frame from synced player state and forwards TrickManager's
## combo bank/void events, then shows every challenge as a column on the live leaderboard.
## Add subclass .tres files to GameModeEventDefinition.race_challenges.
## See planning_docs/StuntRaceGamemode.md.
class_name RaceChallenge extends Resource

@export var title_key: String = ""
## Leaderboard column header — an emoji for now.
@export var icon: String = ""

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


## A combo ended cleanly and TrickManager banked it. Override in the subclass.
func on_combo_banked(_peer_id: int, _points: float) -> void:
	pass


## A crash voided the combo in progress — nothing from it may count. Override in the subclass.
func on_combo_voided(_peer_id: int) -> void:
	pass


func get_best(peer_id: int) -> float:
	return _best.get(peer_id, 0.0)


## Human-readable value, e.g. "4.2s". Override in the subclass.
func format_value(_value: float) -> String:
	return ""


## Localized challenge name for the leaderboard/results.
func title() -> String:
	return tr(title_key)


## Tricks the HUD shows (with how to do them) while this challenge runs. Override in the subclass.
func hint_tricks() -> PackedInt32Array:
	return PackedInt32Array()
