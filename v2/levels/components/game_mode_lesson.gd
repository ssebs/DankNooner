@tool
## One step inside a gamemode course. Reusable across tutorial / race / future modes.
##
## - objective : the WHAT (Resource subclass with check/on_enter/on_exit/get_progress)
## - eval_when : the WHEN (every tick / one-shot on trigger enter / accumulate while inside)
## - trigger   : the WHERE (a GameModeObject scene node — required for ON_ENTER / WHILE_INSIDE)
##
## Lessons live as children of an EventStartCircle and are discovered in tree order.
class_name GameModeLesson extends Node

enum EvalWhen { ALWAYS, ON_ENTER, WHILE_INSIDE }

@export var objective: Objective
@export var eval_when: EvalWhen = EvalWhen.ALWAYS
@export var trigger: GameModeObject


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	if objective == null:
		issues.append("objective must be set")
	if eval_when != EvalWhen.ALWAYS and trigger == null:
		issues.append("trigger must be set for ON_ENTER / WHILE_INSIDE")
	return issues
