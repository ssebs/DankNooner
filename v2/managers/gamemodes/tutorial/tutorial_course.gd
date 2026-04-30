@tool
## Ordered set of TutorialLessons placed in a level. Tutorial gamemode finds
## the matching course by `event` resource and walks `lessons` per peer.
##
## Multiple courses can coexist in one level (Basics, Tricks, …). Each course
## binds to a single GameModeEvent.
class_name TutorialCourse extends Node

@export var event: GameModeEvent
@export var lessons: Array[TutorialLesson] = []
@export var start_marker: Marker3D


func _ready():
	add_to_group(UtilsConstants.GROUPS["TutorialCourses"], true)


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	if event == null:
		issues.append("event must be set so the tutorial gamemode can find this course")
	if start_marker == null:
		issues.append("start_marker must be set")
	if lessons.is_empty():
		issues.append("lessons must not be empty")
	return issues
