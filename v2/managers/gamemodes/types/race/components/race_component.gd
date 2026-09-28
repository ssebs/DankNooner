@tool
## Base for a RaceGameMode component — a child node of one RaceGameMode instance in main_game,
## exported on it (PlayerEntity controller pattern). RaceGameMode calls every hook, server-only,
## in its fixed _components order; override the ones you need.
class_name RaceComponent extends Node

@export var race_mode: RaceGameMode


## A fresh race: Enter and restart.
func race_start() -> void:
	pass


## Every frame while a leg is live (not during the results screen).
func tick(_delta: float) -> void:
	pass


## A human crossed the finish line of the event's last runner.
func racer_finished(_peer_id: int) -> void:
	pass


## Exit and restart (before the next race_start).
func race_end() -> void:
	pass


## This component's share of a human's STUNT_RACE standing.
func score(_peer_id: int) -> float:
	return 0.0


## Extra leaderboard/results columns — header icons, one cell each via column_cells.
func column_headers() -> PackedStringArray:
	return PackedStringArray()


func column_cells(_peer_id: int) -> PackedStringArray:
	return PackedStringArray()


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	if race_mode == null:
		issues.append("race_mode must not be empty")
	return issues
