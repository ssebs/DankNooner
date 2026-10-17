## Remappable controls (UtilsConstants.CONTROL_CATEGORIES). Defaults are the project Input Map;
## settings.json "controls" holds overrides as {action: {slot: event dict, or null if cleared}}.
## Static-only — never instanced.
class_name ControlBindings

## One event per slot. kbm takes keys/mouse, gamepad takes pad input, addl takes either.
const SLOTS: Array[String] = ["kbm", "gamepad", "addl"]


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
