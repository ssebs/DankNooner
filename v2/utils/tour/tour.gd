@tool
## A one-time onboarding walkthrough, played by TourManager.
##
## Tree: Tour > TourStep (one or more, shown in tree order). Step 0 is always the intro modal.
## Step body text names controls with {action} tokens (InputMap action names, e.g. {throttle}),
## which render as the player's live button icons.
class_name Tour extends Node

## Save key; must be unique across the game.
@export var tour_id: StringName
## Short version for the HUD's event pane; "" = the last page's body.
@export var summary_key: String = ""


func get_steps() -> Array[TourStep]:
	var steps: Array[TourStep] = []
	for child in get_children():
		if child is TourStep:
			steps.append(child)
	return steps


func get_pane_key() -> String:
	return summary_key if summary_key != "" else get_steps()[-1].body_key


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	if tour_id == &"":
		issues.append("tour_id must be set")
	if get_steps().is_empty():
		issues.append("Add at least one TourStep child")
	return issues
