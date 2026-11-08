@tool
## One step of a Tour. Body text may use {action} tokens for live button icons.
class_name TourStep extends Node

@export var title_key: String
@export var body_key: String
## Optional highlighted line.
@export var warning_key: String = ""
## Unused for now; the panel layout reserves room for it.
@export var image: Texture2D
## Control, Node3D, or null to center the step. Ignored on step 0 (the intro modal).
@export var target: Node

## Set at runtime by the owning scene to make this an action step: Next hides, input passes
## to the game, and the tour moves on once this returns true.
var done_when: Callable


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	if title_key.is_empty():
		issues.append("title_key must be set")
	if target != null and !(target is Control or target is Node3D):
		issues.append("target must be a Control, a Node3D, or empty")
	return issues
