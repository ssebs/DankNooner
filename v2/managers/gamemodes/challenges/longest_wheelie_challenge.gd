@tool
## Whole-race challenge: track each rider's single longest continuous wheelie hold.
## The wheelie check mirrors WheelieDurationTask (either wheelie variant counts).
class_name LongestWheelieChallenge extends RaceChallenge

@export var title_key: String = "RACE_LONGEST_WHEELIE"

## peer_id -> current continuous hold (seconds); zeroes the frame the wheelie drops.
var _run: Dictionary[int, float] = {}


func reset(peer_ids: Array) -> void:
	super.reset(peer_ids)
	_run.clear()
	for peer_id in peer_ids:
		_run[peer_id] = 0.0


func tick(peer_id: int, player: PlayerEntity, delta: float) -> void:
	var is_wheelie := (
		player.trick_controller.current_trick
		in [TrickController.Trick.WHEELIE_SITTING, TrickController.Trick.WHEELIE_MOD]
	)
	if !is_wheelie:
		_run[peer_id] = 0.0
		return
	_run[peer_id] = _run.get(peer_id, 0.0) + delta
	_best[peer_id] = maxf(_best.get(peer_id, 0.0), _run[peer_id])


func format_value(value: float) -> String:
	return "%.1fs" % value


func title() -> String:
	return tr(title_key)


func hint_tricks() -> PackedInt32Array:
	return PackedInt32Array([TrickController.Trick.WHEELIE_SITTING])
