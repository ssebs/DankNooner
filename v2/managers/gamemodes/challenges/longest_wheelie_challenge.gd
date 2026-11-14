@tool
## Whole-race challenge: track each rider's single longest continuous wheelie hold, from
## TrickManager's banked holds (either wheelie variant counts), so a crash voids it with its combo.
class_name LongestWheelieChallenge extends RaceChallenge


func on_combo_banked(peer_id: int, _points: float, holds: Dictionary) -> void:
	var runs: Array = holds.get(TrickController.Trick.WHEELIE_SITTING, [0.0])
	_best[peer_id] = maxf(_best.get(peer_id, 0.0), runs.max())


func format_value(value: float) -> String:
	return "%.1fs" % value


func hint_tricks() -> PackedInt32Array:
	return PackedInt32Array([TrickController.Trick.WHEELIE_SITTING])
