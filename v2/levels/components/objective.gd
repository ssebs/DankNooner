## Generic, gamemode-agnostic objective. A GameModeLesson holds one Objective and
## decides WHEN to evaluate it (every tick / on trigger enter / while inside trigger).
##
## `state` is a per-player Dictionary owned by the gamemode. Mutate freely.
## Cleared on lesson advance and on crash.
class_name Objective extends Resource


func check(_player: PlayerEntity, _delta: float, _state: Dictionary) -> bool:
	return false


func on_enter(_player: PlayerEntity, _state: Dictionary) -> void:
	pass


func on_exit(_player: PlayerEntity, _state: Dictionary) -> void:
	pass


func get_progress(_state: Dictionary) -> String:
	return ""


func get_objective_text() -> String:
	return ""


func get_hint_text() -> String:
	return ""
