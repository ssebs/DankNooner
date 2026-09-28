@tool
## Rolls pick_count tricks from trick_pool each race; TrickManager scores them 2x. No leaderboard
## column (leave title_key empty) — the picks show as the riding HUD's hint trick rows.
class_name SuggestedTricksChallenge extends RaceChallenge

@export var trick_pool: Array[TrickController.Trick] = []
@export var pick_count: int = 2

var _picks := PackedInt32Array()


func reset(peer_ids: Array) -> void:
	super.reset(peer_ids)
	var pool := trick_pool.duplicate()
	pool.shuffle()
	_picks = PackedInt32Array(pool.slice(0, pick_count))


func hint_tricks() -> PackedInt32Array:
	return _picks


func bonus_tricks() -> PackedInt32Array:
	return _picks
