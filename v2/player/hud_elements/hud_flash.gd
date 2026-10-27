@tool
## Neon flash for a HUD panel: tints its self_modulate (its own stylebox, not its children's text)
## and eases back to white. Channels over 1 brighten the neon theme's baked glow.
## Static-only — never instanced.
class_name HUDFlash

const _TWEEN_META := &"hud_flash_tween"


## A new flash replaces one still running on the same item.
static func flash(item: CanvasItem, color: Color, secs: float) -> void:
	var running: Tween = item.get_meta(_TWEEN_META, null)
	if running != null:
		running.kill()
	item.self_modulate = color
	var tween := item.create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(item, "self_modulate", Color.WHITE, secs)
	item.set_meta(_TWEEN_META, tween)
