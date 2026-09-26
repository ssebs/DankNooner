@tool
class_name ResultsHUDState extends HUDState

signal skip_pressed
signal restart_pressed

@export var input_state_manager: InputStateManager

@onready var title_label: Label = %TitleLabel
@onready var results_board: RaceLeaderboard = %ResultsBoard
@onready var countdown_label: Label = %CountdownLabel
@onready var skip_btn: Button = %SkipBtn
@onready var restart_btn: Button = %RestartBtn

var _countdown: float = -1.0


func _ready():
	ui.hide()
	skip_btn.pressed.connect(func(): skip_pressed.emit())
	restart_btn.pressed.connect(func(): restart_pressed.emit())


func _process(delta: float):
	if _countdown <= 0.0:
		return
	_countdown -= delta
	countdown_label.text = "%d" % ceili(_countdown)
	if _countdown <= 0.0:
		_countdown = -1.0


@rpc("call_local", "reliable")
func rpc_show_results(results_dict: Dictionary, countdown_seconds: float):
	var data := ResultsData.from_dict(results_dict)
	title_label.text = data.title
	# A fresh results screen — don't slide rows over from the last one.
	results_board.clear()
	_rebuild_rows(data)
	_countdown = countdown_seconds
	countdown_label.text = "%d" % ceili(countdown_seconds)
	skip_btn.visible = multiplayer.is_server()
	restart_btn.visible = multiplayer.is_server()
	input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME_PAUSED
	ui.show()
	if skip_btn.visible:
		skip_btn.call_deferred("grab_focus")


## Refresh title + rows only — countdown, focus and input state are untouched, so
## this is safe to call repeatedly while the results screen is up.
@rpc("call_local", "reliable")
func rpc_update_rows(results_dict: Dictionary):
	var data := ResultsData.from_dict(results_dict)
	title_label.text = data.title
	_rebuild_rows(data)


@rpc("call_local", "reliable")
func rpc_hide():
	_countdown = -1.0
	input_state_manager.current_input_state = InputStateManager.InputState.IN_GAME
	ui.hide()


## Rows with a _peer_id tween by it and highlight the local player's; the rest key by rank,
## offset clear of real peer ids (positive) and NPC ids (small negative).
func _rebuild_rows(data: ResultsData):
	var rows: Array = []
	for i in data.rows.size():
		var row := data.rows[i]
		var cells := PackedStringArray()
		for col in data.columns:
			cells.append(str(row.get(col, "")))
		rows.append({"peer_id": row.get("_peer_id", -1_000_000 - i), "cells": cells})
	results_board.set_board(PackedStringArray(data.headers), rows)


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if input_state_manager == null:
		issues.append("input_state_manager must not be empty")
	return issues
