@tool
## Hold a wheelie (sitting or mod) for `duration` seconds.
class_name WheelieDurationTask extends GameModeTask

@export var duration: float = 2.0
## Only a balance-locked wheelie counts.
@export var locked: bool = false
## Only time in the balance point counts (within one wheelie).
@export var balance_point: bool = false
## Only a wheelie popped by a clutch dump counts.
@export var clutch_up: bool = false

## A clutch-up's front comes up at most this long after the clutch dump.
const CLUTCH_UP_GRACE: float = 0.5


func check(player: PlayerEntity, delta: float, state: Dictionary) -> bool:
	var movement := player.movement_controller
	var is_wheelie := (
		player.trick_controller.current_trick
		in [TrickController.Trick.WHEELIE_SITTING, TrickController.Trick.WHEELIE_MOD]
	)
	if !is_wheelie:
		state.erase("t")
		var since_dump: float = state.get("since_dump", INF) + delta
		state["since_dump"] = 0.0 if movement.is_clutch_dumping() else since_dump
		return false
	if !state.has("t"):
		# The wheelie just started.
		state["t"] = 0.0
		state["popped"] = state.get("since_dump", INF) <= CLUTCH_UP_GRACE
	if (locked and !movement.balance_locked) or (clutch_up and !state["popped"]):
		state["t"] = 0.0
		return false
	# Pauses rather than resets: holding the balance point unlocked is hard (locking comes next).
	if balance_point and !movement.in_balance_point:
		return false
	state["t"] += delta
	return state["t"] >= duration


func get_progress(state: Dictionary) -> String:
	return "%.1f / %.1fs" % [state.get("t", 0.0), duration]


func get_objective_text() -> String:
	var key := "TUT_DO_WHEELIE"
	if locked:
		key = "TUT_LOCK_WHEELIE"
	elif balance_point:
		key = "TUT_BALANCE_WHEELIE"
	elif clutch_up:
		key = "TUT_CLUTCH_UP"
	return tr(key).format({"duration": duration})
