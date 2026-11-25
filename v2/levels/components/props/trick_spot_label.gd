## Floating callout naming a trick spot ("BIG AIR", "RAIL"), added at runtime by Ramp and the grind
## rail. Shown only during events (events_active), fading in past NEAR_M and out toward FAR_M from
## the camera, so it points the way without covering the run-in. A bonus ramp
## (BonusRampComponent) swaps in its own callout, gold and seen from further away.
class_name TrickSpotLabel extends Label3D

const NEAR_M: float = 15.0
const FAR_M: float = 120.0
const BONUS_FAR_M: float = 300.0
## Metres each edge fades over.
const FADE_M: float = 15.0
const SPOT_COLOR := Color.WHITE
const BONUS_COLOR := UtilsConstants.UI_GOLD

## Set every frame by RidingHUDState: true outside free roam.
static var events_active: bool = false

var _spot_text: String = ""
var _bonus: bool = false


## text_key: the spot's localization key.
func _init(text_key: String = "") -> void:
	_spot_text = text_key
	text = text_key
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fixed_size = true
	pixel_size = 0.0015
	font_size = 32
	outline_size = 10
	modulate = SPOT_COLOR
	visible = false


## Empty `bonus_text` (already localized) reverts to the spot's own callout.
func set_bonus(bonus_text: String) -> void:
	_bonus = bonus_text != ""
	text = bonus_text if _bonus else _spot_text
	modulate = BONUS_COLOR if _bonus else SPOT_COLOR


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	# No camera between level swaps — skip is intentional
	if !events_active or cam == null:
		visible = false
		return
	var dist := cam.global_position.distance_to(global_position)
	var far := BONUS_FAR_M if _bonus else FAR_M
	var alpha := clampf((dist - NEAR_M) / FADE_M, 0.0, 1.0) * clampf((far - dist) / FADE_M, 0.0, 1.0)
	visible = alpha > 0.0
	modulate.a = alpha
	outline_modulate.a = alpha
