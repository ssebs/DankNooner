## Button prompt: the glyph `action` is bound to on the rider's current device.
class_name InputPrompt extends HBoxContainer

@export var action: String

@onready var _icon: TextureRect = %Icon
@onready var _key: Label = %Key


## Called by RidingHUDState on a device switch and whenever the HUD shows (bindings may have changed).
func refresh(gamepad: bool) -> void:
	var event := ControlBindings.event_for(action, gamepad)
	# The slot can be cleared in Settings > Controls — nothing to prompt then.
	visible = event != null
	if event == null:
		return
	_icon.texture = ControlBindings.event_icon(event)
	_icon.visible = _icon.texture != null
	_key.text = ControlBindings.event_text(event)
	_key.visible = _key.text != ""
