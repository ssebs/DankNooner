@tool
## Segmented boost meter — one cell per boost segment. Fed from HUDController each frame
## off PlayerEntity.boost_amount (which is measured in segments).
##
## Reads at a glance as one of three states, because a press is silently rejected below one
## full segment and that needs to be obvious before the player tries:
##   - below 1 segment  -> dim, no glow ("not yet")
##   - 1+ segments      -> bright blue with a slow glow pulse ("ready")
##   - all cells full   -> faster white shimmer ("spend all 3 for the long burn")
##
##  [||||||][||||||][......]
class_name BoostGauge extends Control

## Meter fill in segments, 0..cell count. Set every frame by HUDController.
@export var current_val: float = 0.0
## Exponential smoothing rate for each cell's fill — the raw value steps on network ticks.
@export var smooth_speed: float = 14.0

## Unfilled remainder of a cell.
const COLOR_EMPTY: Color = Color(0.22, 0.26, 0.30)
## Filled, but under one whole segment — nothing is spendable yet, so it stays muted.
const COLOR_DIM: Color = Color(0.16, 0.34, 0.48)
## At least one full segment banked — the same blue as the boost camera FX.
const COLOR_READY: Color = Color(0.25, 0.69, 1.0)
## Rejected-press blink.
const COLOR_REJECT: Color = Color(1.0, 0.3, 0.2)

## Slow "ready" glow — pulse rate (Hz) and how far it lifts toward white.
const READY_PULSE_HZ: float = 1.2
const READY_GLOW_AMOUNT: float = 0.3
## Faster, stronger shimmer once every cell is full.
const FULL_PULSE_HZ: float = 3.0
const FULL_GLOW_AMOUNT: float = 0.5
## Extra punch while boost is actually being spent.
const SPENDING_BRIGHTEN: float = 0.5
## Rejected-press blink: total duration and the on/off period within it.
const BLINK_SECS: float = 0.45
const BLINK_PERIOD: float = 0.15

@onready var _cells: Array[Node] = %Cells.get_children()

var _is_spending: bool = false
var _pulse_t: float = 0.0
var _blink_t: float = 0.0


func _process(delta: float):
	if Engine.is_editor_hint():
		return

	var weight := 1.0 - exp(-smooth_speed * delta)
	_pulse_t += delta
	_blink_t = maxf(_blink_t - delta, 0.0)

	# A press needs one whole segment; anything less can't be spent at all.
	var is_ready: bool = current_val >= 1.0
	var all_full: bool = current_val >= float(_cells.size())

	var tint := COLOR_DIM
	if is_ready:
		var hz: float = FULL_PULSE_HZ if all_full else READY_PULSE_HZ
		var amount: float = FULL_GLOW_AMOUNT if all_full else READY_GLOW_AMOUNT
		var glow := (sin(_pulse_t * TAU * hz) * 0.5 + 0.5) * amount
		tint = COLOR_READY.lerp(Color.WHITE, glow)
	if _is_spending:
		tint = tint.lerp(Color.WHITE, SPENDING_BRIGHTEN)
	# Blink overrides everything — it's a direct answer to a button press.
	if _blink_t > 0.0 and fmod(_blink_t, BLINK_PERIOD) > BLINK_PERIOD * 0.5:
		tint = COLOR_REJECT

	for i in _cells.size():
		var cell := _cells[i] as TextureProgressBar
		# Cell i holds the fill between i and i+1 segments.
		var cell_pct: float = clampf(current_val - float(i), 0.0, 1.0)
		cell.value = lerpf(cell.value, cell_pct * 100.0, weight)
		var target := COLOR_EMPTY.lerp(tint, clampf(cell_pct * 4.0, 0.0, 1.0))
		# Snap during a blink instead of easing, or the flash smears into mush.
		cell.tint_progress = target if _blink_t > 0.0 else cell.tint_progress.lerp(target, weight)


## Called by HUDController — drives the extra brighten while boost is being consumed.
func set_spending(spending: bool):
	_is_spending = spending


## Called by HUDController when boost was pressed without a full segment banked.
func flash_rejected():
	_blink_t = BLINK_SECS
