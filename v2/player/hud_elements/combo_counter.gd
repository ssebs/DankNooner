@tool
## Combo multiplier readout. Escalates in drama with the multiplier: bigger, hotter,
## and shakier the higher it climbs, with a punch + flash on every step up.
##
## Fed from HUDController off the synced PlayerEntity.combo_multiplier — the actual
## scoring lives server-side in TrickManager.
class_name ComboCounter extends Control

## Tint per multiplier tier, index 0 = x1. The last entry is reused past the end.
const TIER_COLORS: Array[Color] = [
	Color(0.6, 0.85, 1.0),  # x1 — cool blue
	Color(1.0, 0.72, 0.15),  # x2 — gold
	Color(1.0, 0.25, 0.15),  # x3+ — hot red
]
## Base scale added per tier above x1, so a x3 sits noticeably larger than a x2.
const SCALE_PER_TIER: float = 0.35
## Scale spike applied the instant the multiplier steps up, decaying back to base.
const PUNCH_SCALE: float = 0.9
const PUNCH_DECAY: float = 4.0
## Trauma (0..1) injected on a step up, and the constant floor held per tier above x1.
const PUNCH_TRAUMA: float = 1.0
const TRAUMA_PER_TIER: float = 0.12
const TRAUMA_DECAY: float = 2.0
## Shake displacement (px) at full trauma.
const SHAKE_MAX_PX: float = 14.0
## Idle throb rate (Hz) and depth, scaled by tier — a high combo never sits still.
const THROB_HZ: float = 2.5
const THROB_PER_TIER: float = 0.04
## Fade rate when the combo drops back to x1.
const FADE_SPEED: float = 6.0

@onready var _label: Label = %ComboLabel

var _multiplier: int = 1
## Whether a combo is running at all. Visibility keys off this rather than the multiplier —
## otherwise nothing shows until x2 (10s of trick time) and the meter looks broken.
var _active: bool = false
var _punch: float = 0.0
var _trauma: float = 0.0
var _throb_t: float = 0.0
var _base_pos: Vector2 = Vector2.ZERO


func _ready():
	if Engine.is_editor_hint():
		return
	_base_pos = _label.position
	_label.modulate.a = 0.0


func _process(delta: float):
	if Engine.is_editor_hint():
		return

	# Re-set every frame: the label's size isn't laid out yet in _ready, and scaling
	# around the default top-left pivot makes the punch lurch instead of pop.
	_label.pivot_offset = _label.size / 2.0

	var tier: int = maxi(_multiplier - 1, 0)
	_punch = maxf(_punch - PUNCH_DECAY * delta, 0.0)
	_trauma = maxf(_trauma - TRAUMA_DECAY * delta, TRAUMA_PER_TIER * tier)
	_throb_t += delta

	# Scale: tier baseline + decaying punch + a tier-scaled throb.
	var throb := sin(_throb_t * TAU * THROB_HZ) * THROB_PER_TIER * tier
	var s: float = 1.0 + SCALE_PER_TIER * tier + _punch * PUNCH_SCALE + throb
	_label.scale = Vector2(s, s)

	# Shake — trauma squared so low values stay calm and high ones get violent.
	var shake := _trauma * _trauma * SHAKE_MAX_PX
	_label.position = _base_pos + Vector2(
		randf_range(-shake, shake), randf_range(-shake, shake)
	)

	# The punch flashes toward white before settling into the tier color.
	var color: Color = TIER_COLORS[mini(tier, TIER_COLORS.size() - 1)].lerp(Color.WHITE, _punch)
	# Only visible while actually comboing.
	var target_alpha: float = 1.0 if _active else 0.0
	color.a = move_toward(_label.modulate.a, target_alpha, FADE_SPEED * delta)
	_label.modulate = color


## Called every frame by HUDController. Steps up fire the punch; drops reset quietly.
func set_combo(value: int, active: bool):
	_active = active
	if value != _multiplier:
		if value > _multiplier:
			_punch = 1.0
			_trauma = PUNCH_TRAUMA
		_multiplier = value
	# Assigned unconditionally: _multiplier starts at 1 and the first live call is also 1,
	# so an early-out on "unchanged" left the label showing the scene's placeholder forever.
	# Label.set_text() already no-ops on an identical string, so this is free.
	_label.text = tr("HUD_COMBO").format({"value": _multiplier})


## Called from HUDController.do_reset()
func do_reset():
	_multiplier = 1
	_active = false
	_punch = 0.0
	_trauma = 0.0
	_label.modulate.a = 0.0
