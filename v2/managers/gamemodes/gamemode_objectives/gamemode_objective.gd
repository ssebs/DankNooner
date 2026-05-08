@tool
## Base class for one step in a gamemode course (tutorial / race / future modes).
##
## Lives as a child of an EventStartCircle. The gamemode walks children in tree
## order. Each subclass is a self-contained Node — it can hold its own RPCs and
## @export the managers it needs. Shared across all peers; per-peer scratchpad
## lives in the gamemode's `state` Dictionary, passed into every hook.
##
## - eval_when : ALWAYS / ON_ENTER / WHILE_INSIDE
## - trigger   : required for ON_ENTER / WHILE_INSIDE — a level-authored GameModeObject
class_name GameModeObjective extends Node

enum EvalWhen { ALWAYS, ON_ENTER, WHILE_INSIDE }

@export var eval_when: EvalWhen = EvalWhen.ALWAYS
@export var trigger: GameModeObject

## Set by the gamemode on Enter so steps can call back (e.g. server-side ack RPCs).
var _gamemode: GameMode


func on_enter(_player: PlayerEntity, _state: Dictionary) -> void:
	pass


func check(_player: PlayerEntity, _delta: float, _state: Dictionary) -> bool:
	return false


func on_exit(_player: PlayerEntity, _state: Dictionary) -> void:
	pass


func get_progress(_state: Dictionary) -> String:
	return ""


func get_objective_text() -> String:
	return ""


func get_hint_text() -> String:
	return ""


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	if eval_when != EvalWhen.ALWAYS and trigger == null:
		issues.append("trigger must be set for ON_ENTER / WHILE_INSIDE")
	return issues
