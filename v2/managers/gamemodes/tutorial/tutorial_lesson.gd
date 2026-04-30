@tool
## One step inside a TutorialCourse. References a TutorialSteps.Step (the predicate)
## and decides WHEN that predicate is evaluated:
##   - TIME           — every tick (legacy behavior, no props needed)
##   - PROP_EVENT     — only when one of `trigger_objects` fires `entered` (e.g. gate)
##   - PROP_BOUNDED   — only while the player is inside one of `trigger_objects` (zone)
class_name TutorialLesson extends Node

enum TriggerMode { TIME, PROP_EVENT, PROP_BOUNDED }

@export var step: TutorialSteps.Step
@export var trigger_mode: TriggerMode = TriggerMode.TIME
@export var trigger_objects: Array[GameModeObject] = []
## Optional override for the per-Step objective text key.
@export var objective_text_key: String = ""


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	if trigger_mode != TriggerMode.TIME and trigger_objects.is_empty():
		issues.append("trigger_objects must not be empty for PROP_EVENT / PROP_BOUNDED modes")
	return issues
