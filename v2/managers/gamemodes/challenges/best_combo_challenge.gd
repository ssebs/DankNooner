@tool
## Whole-race challenge: each rider's highest-scoring single combo. Fed from TrickManager's
## bank event, so a combo voided by a crash never reaches it.
class_name BestComboChallenge extends RaceChallenge


func on_combo_banked(peer_id: int, points: float) -> void:
	_best[peer_id] = maxf(_best.get(peer_id, 0.0), points)


func format_value(value: float) -> String:
	return "%d" % int(value)
