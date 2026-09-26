@tool
## Whole-race challenge: track each rider's single longest continuous wheelie hold.
## The wheelie check mirrors WheelieDurationTask (either wheelie variant counts).
## A wheelie always runs inside a combo, so its hold only counts once that combo banks —
## crashing voids it along with the combo.
class_name LongestWheelieChallenge extends RaceChallenge

## peer_id -> current continuous hold (seconds); zeroes the frame the wheelie drops.
var _run: Dictionary[int, float] = {}
## peer_id -> longest hold in the combo in progress, committed to _best when it banks.
var _pending: Dictionary[int, float] = {}


func reset(peer_ids: Array) -> void:
	super.reset(peer_ids)
	_run.clear()
	_pending.clear()
	for peer_id in peer_ids:
		_run[peer_id] = 0.0
		_pending[peer_id] = 0.0


func tick(peer_id: int, player: PlayerEntity, delta: float) -> void:
	var is_wheelie := (
		not player.is_crashed
		and player.trick_controller.current_trick
		in [TrickController.Trick.WHEELIE_SITTING, TrickController.Trick.WHEELIE_MOD]
	)
	if !is_wheelie:
		_run[peer_id] = 0.0
		return
	_run[peer_id] = _run.get(peer_id, 0.0) + delta
	_pending[peer_id] = maxf(_pending.get(peer_id, 0.0), _run[peer_id])


func on_combo_banked(peer_id: int, _points: float) -> void:
	_best[peer_id] = maxf(_best.get(peer_id, 0.0), _pending.get(peer_id, 0.0))
	_pending[peer_id] = 0.0


func on_combo_voided(peer_id: int) -> void:
	_run[peer_id] = 0.0
	_pending[peer_id] = 0.0


func format_value(value: float) -> String:
	return "%.1fs" % value


func hint_tricks() -> PackedInt32Array:
	return PackedInt32Array([TrickController.Trick.WHEELIE_SITTING])
