@tool
## The HUD's shared motion verbs, one meaning each, so the juice reads instead of adding noise:
##   pop      a value went up
##   wheelie  a callout arrived: tilts back off its bottom-left corner (the logo's lifting "o")
##   punch    a tier changed
##   shake    danger only
##   flash_in a new line: tints, fades and slides in
## Static-only — never instanced. A verb replaces the same verb still running on that item.
class_name HUDFlash

const POP_SCALE: float = 1.3
const POP_SECS: float = 0.3
const PUNCH_SCALE: float = 1.5
const PUNCH_SECS: float = 0.45
## Negative tilts back (counter-clockwise).
const WHEELIE_RAD: float = -0.35
const WHEELIE_SECS: float = 0.4
const SHAKE_PX: float = 4.0
const SHAKE_SECS: float = 0.35
const SHAKE_STEPS: int = 7
const FLASH_SECS: float = 0.8
const SLIDE_PX: float = 24.0
const SLIDE_SECS: float = 0.2


static func pop(item: Control) -> void:
	_scale_from(item, POP_SCALE, POP_SECS)


static func punch(item: Control) -> void:
	_scale_from(item, PUNCH_SCALE, PUNCH_SECS)


static func wheelie(item: Control) -> void:
	item.pivot_offset = Vector2(0.0, item.size.y)
	item.rotation = WHEELIE_RAD
	var tween := _restart(item, &"hud_wheelie").set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(item, "rotation", 0.0, WHEELIE_SECS)


## Rattles about where the item is now. A shake still running is left to finish, so a restart
## can't strand the item off its spot.
static func shake(item: Control) -> void:
	if item.has_meta(&"hud_shake") and (item.get_meta(&"hud_shake") as Tween).is_running():
		return
	var base := item.position
	var tween := _restart(item, &"hud_shake")
	var step := SHAKE_SECS / (SHAKE_STEPS + 1)
	for i in SHAKE_STEPS:
		var px := SHAKE_PX * (1.0 - float(i) / SHAKE_STEPS)
		tween.tween_property(item, "position", base + Vector2(randf_range(-px, px), randf_range(-px, px)), step)
	tween.tween_property(item, "position", base, step)


## color tints the item's self_modulate (channels over 1 brighten) and eases back to white. Slides
## in from SLIDE_PX left of where it is.
static func flash_in(item: Control, color: Color) -> void:
	item.self_modulate = color
	item.modulate.a = 0.0
	var tween := _restart(item, &"hud_flash_in").set_parallel()
	tween.tween_property(item, "self_modulate", Color.WHITE, FLASH_SECS).set_trans(Tween.TRANS_EXPO).set_ease(
		Tween.EASE_OUT
	)
	tween.tween_property(item, "modulate:a", 1.0, SLIDE_SECS)
	tween.tween_property(item, "position:x", item.position.x, SLIDE_SECS).from(item.position.x - SLIDE_PX)


static func _scale_from(item: Control, peak: float, secs: float) -> void:
	item.pivot_offset = item.size / 2.0
	item.scale = Vector2.ONE * peak
	var tween := _restart(item, &"hud_scale").set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(item, "scale", Vector2.ONE, secs)


static func _restart(item: Node, key: StringName) -> Tween:
	# get_meta's null default counts as no default, so it errors on the first call.
	if item.has_meta(key):
		(item.get_meta(key) as Tween).kill()
	var tween := item.create_tween()
	item.set_meta(key, tween)
	return tween
