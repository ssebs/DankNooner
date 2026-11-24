@tool
## Button prompt: the glyph `action` is bound to on the rider's current device.
class_name InputPrompt extends HBoxContainer

@export var action: String

@onready var _icon: TextureRect = %Icon
@onready var _key: Label = %Key


func _ready():
	# Editor preview: InputMap only has built-in actions there, so read the project's KBM defaults.
	if Engine.is_editor_hint() and action != "":
		_key.text = _key_text(ProjectSettings.get_setting("input/" + action)["events"], false)


## Called by RidingHUDState on a device switch and whenever the HUD shows (bindings may have changed).
func refresh(gamepad: bool) -> void:
	var event := ControlBindings.event_for(action, gamepad)
	# The slot can be cleared in Settings > Controls — nothing to prompt then.
	visible = event != null
	if event == null:
		return
	_icon.texture = ControlBindings.event_icon(event)
	_icon.visible = _icon.texture != null
	_key.text = _key_text(InputMap.action_get_events(action), gamepad)
	_key.visible = _key.text != ""


## The key fills blue while its action is held.
func set_held(held: bool) -> void:
	_key.theme_type_variation = &"HeldKeyLabel" if held else &"GestureChipLabel"
	_icon.modulate = UtilsConstants.UI_BLUE if held else Color.WHITE


## Every key/mouse binding on this device, e.g. trick reads "T / Right Click".
func _key_text(events: Array, gamepad: bool) -> String:
	var texts := PackedStringArray()
	for bound: InputEvent in events:
		if ControlBindings.is_gamepad(bound) == gamepad and ControlBindings.event_text(bound) != "":
			texts.append(tr(ControlBindings.event_text(bound)))
	return " / ".join(texts)
