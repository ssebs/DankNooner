@tool
## Combo multiplier readout: gold, shown while comboing, punching (HUDFlash) on every step up.
##
## Fed from HUDController off the synced TrickController.combo_multiplier — the actual
## scoring lives server-side in TrickManager.
class_name ComboCounter extends Control

const COLOR := UtilsConstants.UI_GOLD
## Fade rate in and out with the combo.
const FADE_SPEED: float = 6.0

@onready var _label: Label = %ComboLabel

var _multiplier: int = 1
## Whether a combo is running at all. Visibility keys off this rather than the multiplier —
## otherwise nothing shows until x2 (10s of trick time) and the meter looks broken.
var _active: bool = false


func _ready():
	if Engine.is_editor_hint():
		return
	_label.modulate = Color(COLOR, 0.0)


func _process(delta: float):
	if Engine.is_editor_hint():
		return
	var target_alpha: float = 1.0 if _active else 0.0
	_label.modulate.a = move_toward(_label.modulate.a, target_alpha, FADE_SPEED * delta)


## Called every frame by HUDController. Steps up punch; drops reset quietly.
func set_combo(value: int, active: bool):
	_active = active
	if value > _multiplier:
		HUDFlash.punch(_label)
	_multiplier = value
	# Assigned unconditionally: _multiplier starts at 1 and the first live call is also 1,
	# so an early-out on "unchanged" left the label showing the scene's placeholder forever.
	# Label.set_text() already no-ops on an identical string, so this is free.
	_label.text = tr("HUD_COMBO").format({"value": _multiplier})


## Called from HUDController.do_reset()
func do_reset():
	_multiplier = 1
	_active = false
	_label.modulate.a = 0.0
