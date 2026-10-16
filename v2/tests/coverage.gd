extends RefCounted
## Compares the game against the gym level, so the gym can't silently fall behind: every
## gamemode Kind, every GameModeTask subclass, every FreeRoamActivity subclass. A gap fails the
## run, except the optional ones below, which only warn that they go untested.

## No tutorial in the gym; these tasks only make sense in one
const SKIPPED_KINDS: Array[int] = [GameModeType.Kind.FREE_ROAM, GameModeType.Kind.TUTORIAL]
const TUTORIAL_ONLY_TASKS: Array[String] = [
	"CloseHelpTask", "ShowSpeechBubbleTask", "HideSpeechBubbleTask"
]
## Not in the gym by choice. Delete an entry once the gym has it.
const OPTIONAL_KINDS: Array[int] = [GameModeType.Kind.STUNT_CHALLENGE]
const OPTIONAL_TASKS: Array[String] = [
	"ChangeGearTask", "GridRespawnTask", "MaintainTrickTask", "PerformTrickTask",
	"SpeedAboveTask", "StoppieDurationTask", "TeleportTask", "WheelieDurationTask",
]


## {"gaps": failing messages, "untested": warnings for optional gaps}
static func check(tree: SceneTree) -> Dictionary:
	var kinds := {}
	var has_fuel_up := false
	var tasks := {}
	for circle: EventStartCircle in tree.get_nodes_in_group(UtilsConstants.GROUPS["EventCircles"]):
		for event in circle.get_events():
			kinds[event.definition.target_gamemode] = true
			has_fuel_up = has_fuel_up or event.definition.fuel_up_first
			for node in event.find_children("*", "", true, false):
				if node is GameModeTask:
					tasks[(node.get_script() as Script).get_global_name()] = true
	var activities := {}
	for activity in tree.get_nodes_in_group(UtilsConstants.GROUPS["FreeRoamActivities"]):
		activities[(activity.get_script() as Script).get_global_name()] = true

	var gaps: Array[String] = []
	var untested: Array[String] = []
	for kind_name in GameModeType.Kind.keys():
		var kind: int = GameModeType.Kind[kind_name]
		if kind in SKIPPED_KINDS:
			continue
		var covered := has_fuel_up if kind == GameModeType.Kind.FUEL_UP else kinds.has(kind)
		if !covered:
			var message := "gym has no %s event" % kind_name
			(untested if kind in OPTIONAL_KINDS else gaps).append(message)
	for task_class in _subclasses("GameModeTask", "TaskRunner"):
		if task_class not in TUTORIAL_ONLY_TASKS and !tasks.has(task_class):
			var message := "gym uses no %s" % task_class
			(untested if task_class in OPTIONAL_TASKS else gaps).append(message)
	for activity_class in _subclasses("FreeRoamActivity", ""):
		if !activities.has(activity_class):
			gaps.append("gym has no %s" % activity_class)
	return {"gaps": gaps, "untested": untested}


## Global classes deriving from `root`, minus `root` and anything deriving from `excluded`.
static func _subclasses(root: String, excluded: String) -> Array[String]:
	var bases := {}
	for entry in ProjectSettings.get_global_class_list():
		bases[entry["class"]] = entry["base"]
	var found: Array[String] = []
	for name: String in bases:
		var lineage := [name]
		while bases.has(lineage.back()):
			lineage.append(bases[lineage.back()])
		if root in lineage.slice(1) and excluded not in lineage:
			found.append(name)
	return found
