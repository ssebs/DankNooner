## Remappable controls (UtilsConstants.CONTROL_CATEGORIES). Defaults are the project Input Map;
## settings.json "controls" holds overrides as {action: {slot: event dict, or null if cleared}}.
## Static-only — never instanced.
class_name ControlBindings

## One event per slot. kbm takes keys/mouse, gamepad takes pad input, addl takes either.
const SLOTS: Array[String] = ["kbm", "gamepad", "addl"]

## Only these buttons/axes are bindable, so every binding has a label or icon.
const MOUSE_BUTTON_LABELS: Dictionary = {
	MOUSE_BUTTON_LEFT: "MOUSE_LEFT_LABEL",
	MOUSE_BUTTON_RIGHT: "MOUSE_RIGHT_LABEL",
	MOUSE_BUTTON_MIDDLE: "MOUSE_MIDDLE_LABEL",
	MOUSE_BUTTON_WHEEL_UP: "MOUSE_WHEEL_UP_LABEL",
	MOUSE_BUTTON_WHEEL_DOWN: "MOUSE_WHEEL_DOWN_LABEL",
	MOUSE_BUTTON_XBUTTON1: "MOUSE_BACK_LABEL",
	MOUSE_BUTTON_XBUTTON2: "MOUSE_FORWARD_LABEL",
}
const JOY_BUTTON_ICONS: Dictionary = {
	JOY_BUTTON_A: preload("res://resources/img/Icons/xbox_button_color_a.svg"),
	JOY_BUTTON_B: preload("res://resources/img/Icons/xbox_button_color_b.svg"),
	JOY_BUTTON_X: preload("res://resources/img/Icons/xbox_button_color_x.svg"),
	JOY_BUTTON_Y: preload("res://resources/img/Icons/xbox_button_color_y.svg"),
	JOY_BUTTON_BACK: preload("res://resources/img/Icons/xbox_button_view.svg"),
	JOY_BUTTON_GUIDE: preload("res://resources/img/Icons/xbox_guide.svg"),
	JOY_BUTTON_START: preload("res://resources/img/Icons/xbox_button_menu.svg"),
	JOY_BUTTON_LEFT_STICK: preload("res://resources/img/Icons/xbox_stick_l_press.svg"),
	JOY_BUTTON_RIGHT_STICK: preload("res://resources/img/Icons/xbox_stick_r_press.svg"),
	JOY_BUTTON_LEFT_SHOULDER: preload("res://resources/img/Icons/xbox_lb.svg"),
	JOY_BUTTON_RIGHT_SHOULDER: preload("res://resources/img/Icons/xbox_rb.svg"),
	JOY_BUTTON_DPAD_UP: preload("res://resources/img/Icons/xbox_dpad_up.svg"),
	JOY_BUTTON_DPAD_DOWN: preload("res://resources/img/Icons/xbox_dpad_down.svg"),
	JOY_BUTTON_DPAD_LEFT: preload("res://resources/img/Icons/xbox_dpad_left.svg"),
	JOY_BUTTON_DPAD_RIGHT: preload("res://resources/img/Icons/xbox_dpad_right.svg"),
	JOY_BUTTON_MISC1: preload("res://resources/img/Icons/xbox_button_share.svg"),
}
## Keyed by axis_key().
const JOY_AXIS_ICONS: Dictionary = {
	Vector2i(JOY_AXIS_LEFT_X, -1): preload("res://resources/img/Icons/xbox_stick_l_left.svg"),
	Vector2i(JOY_AXIS_LEFT_X, 1): preload("res://resources/img/Icons/xbox_stick_l_right.svg"),
	Vector2i(JOY_AXIS_LEFT_Y, -1): preload("res://resources/img/Icons/xbox_stick_l_up.svg"),
	Vector2i(JOY_AXIS_LEFT_Y, 1): preload("res://resources/img/Icons/xbox_stick_l_down.svg"),
	Vector2i(JOY_AXIS_RIGHT_X, -1): preload("res://resources/img/Icons/xbox_stick_r_left.svg"),
	Vector2i(JOY_AXIS_RIGHT_X, 1): preload("res://resources/img/Icons/xbox_stick_r_right.svg"),
	Vector2i(JOY_AXIS_RIGHT_Y, -1): preload("res://resources/img/Icons/xbox_stick_r_up.svg"),
	Vector2i(JOY_AXIS_RIGHT_Y, 1): preload("res://resources/img/Icons/xbox_stick_r_down.svg"),
	Vector2i(JOY_AXIS_TRIGGER_LEFT, 1): preload("res://resources/img/Icons/xbox_lt.svg"),
	Vector2i(JOY_AXIS_TRIGGER_RIGHT, 1): preload("res://resources/img/Icons/xbox_rt.svg"),
}


## Rebuild InputMap for every remappable action from defaults + overrides.
static func apply(overrides: Dictionary):
	for actions in UtilsConstants.CONTROL_CATEGORIES.values():
		for action in actions:
			InputMap.action_erase_events(action)
			var slots := resolve_slots(action, overrides)
			for slot in SLOTS:
				if slots[slot] != null:
					InputMap.action_add_event(action, slots[slot])


## Slot → InputEvent (null when empty). Overrides win over the Input Map default.
static func resolve_slots(action: String, overrides: Dictionary) -> Dictionary:
	var slots := get_default_slots(action)
	var action_overrides: Dictionary = overrides.get(action, {})
	for slot in action_overrides:
		var binding = action_overrides[slot]
		slots[slot] = from_dict(binding) if binding != null else null
	return slots


## Splits the Input Map's events into slots: first of each device type, then the leftover in addl.
static func get_default_slots(action: String) -> Dictionary:
	var slots := {"kbm": null, "gamepad": null, "addl": null}
	# ProjectSettings, not InputMap — apply() overwrites the latter
	for event: InputEvent in ProjectSettings.get_setting("input/" + action)["events"]:
		var slot := "gamepad" if is_gamepad(event) else "kbm"
		if slots[slot] != null:
			slot = "addl"
		assert(slots[slot] == null, "Input Map action %s has more events than slots" % action)
		slots[slot] = event
	return slots


static func is_gamepad(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


static func axis_key(event: InputEventJoypadMotion) -> Vector2i:
	return Vector2i(event.axis, int(signf(event.axis_value)))


## First live InputMap event for action on that device type, or null if that slot is empty.
static func event_for(action: String, gamepad: bool) -> InputEvent:
	for event in InputMap.action_get_events(action):
		if is_gamepad(event) == gamepad:
			return event
	return null


## Pad glyph; null for keys/mouse, which use event_text().
static func event_icon(event: InputEvent) -> Texture2D:
	if event is InputEventJoypadButton:
		return JOY_BUTTON_ICONS[event.button_index]
	if event is InputEventJoypadMotion:
		return JOY_AXIS_ICONS[axis_key(event)]
	return null


## Key name or mouse button loc key; "" for pad input, which uses event_icon().
static func event_text(event: InputEvent) -> String:
	if event is InputEventKey:
		var keycode := DisplayServer.keyboard_get_keycode_from_physical(event.physical_keycode)
		return OS.get_keycode_string(keycode)
	if event is InputEventMouseButton:
		return MOUSE_BUTTON_LABELS[event.button_index]
	return ""


static func accepts(slot: String, event: InputEvent) -> bool:
	match slot:
		"kbm":
			return event is InputEventKey or event is InputEventMouseButton
		"gamepad":
			return is_gamepad(event)
	return true


## JSON-safe form for settings.json, holding only what a binding needs so dicts compare by value.
static func to_dict(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		return {"type": "key", "physical_keycode": event.physical_keycode}
	if event is InputEventMouseButton:
		return {"type": "mouse_button", "button_index": event.button_index}
	if event is InputEventJoypadButton:
		return {"type": "joy_button", "button_index": event.button_index}
	if event is InputEventJoypadMotion:
		return {"type": "joy_motion", "axis": event.axis, "axis_value": signf(event.axis_value)}
	assert(false, "unbindable event %s" % event)
	return {}


## JSON numbers load as floats, hence the int() casts.
static func from_dict(dict: Dictionary) -> InputEvent:
	var event: InputEvent
	match dict["type"]:
		"key":
			event = InputEventKey.new()
			event.physical_keycode = int(dict["physical_keycode"])
		"mouse_button":
			event = InputEventMouseButton.new()
			event.button_index = int(dict["button_index"])
		"joy_button":
			event = InputEventJoypadButton.new()
			event.button_index = int(dict["button_index"])
		"joy_motion":
			event = InputEventJoypadMotion.new()
			event.axis = int(dict["axis"])
			event.axis_value = dict["axis_value"]
	# -1 matches every device, like the Input Map's own events
	event.device = -1
	return event
