@tool
## Live stunt-race leaderboard: a header row, then one row per human sorted by score.
## Rows slide to their new rank on reorder, so they're placed by hand rather than in a
## container (which would snap them). Fed by RidingHUDState from the server's snapshot.
class_name RaceLeaderboard extends Control

const ROW_HEIGHT: float = 26.0
const NAME_WIDTH: float = 130.0
const CELL_WIDTH: float = 64.0
## Duration of the slide to a new rank.
const REORDER_SECS: float = 0.35
const OWN_ROW_COLOR := Color(1.0, 0.8, 0.2)

var _header: HBoxContainer = null
## peer_id -> row, and the rank each row last slid to.
var _rows: Dictionary[int, HBoxContainer] = {}
var _ranks: Dictionary[int, int] = {}


## rows: [{"peer_id": int, "cells": PackedStringArray}], already sorted best-first.
## cells line up with headers (name first).
func set_board(headers: PackedStringArray, rows: Array) -> void:
	if _header == null:
		_header = _add_row()
	_set_cells(_header, headers)

	var live: Dictionary[int, bool] = {}
	for rank in rows.size():
		var peer_id: int = rows[rank]["peer_id"]
		live[peer_id] = true
		if !_rows.has(peer_id):
			var row := _add_row()
			row.position.y = _rank_y(rank)
			if peer_id == multiplayer.get_unique_id():
				row.modulate = OWN_ROW_COLOR
			_rows[peer_id] = row
			_ranks[peer_id] = rank
		elif _ranks[peer_id] != rank:
			_ranks[peer_id] = rank
			var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_property(_rows[peer_id], "position:y", _rank_y(rank), REORDER_SECS)
		_set_cells(_rows[peer_id], rows[rank]["cells"])

	for peer_id in _rows.keys():
		if !live.has(peer_id):
			_rows[peer_id].queue_free()
			_rows.erase(peer_id)
			_ranks.erase(peer_id)

	custom_minimum_size = Vector2(
		NAME_WIDTH + CELL_WIDTH * (headers.size() - 1), _rank_y(rows.size())
	)


func clear() -> void:
	for child in get_children():
		child.queue_free()
	_header = null
	_rows.clear()
	_ranks.clear()


## Header sits at rank -1, so data rank 0 is the second line.
func _rank_y(rank: int) -> float:
	return (rank + 1) * ROW_HEIGHT


func _add_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Widths are summed by hand in set_board — no gaps between cells.
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	return row


## Grows the row's labels to match, then sets their text. First column is the (wider) name.
func _set_cells(row: HBoxContainer, texts: PackedStringArray) -> void:
	while row.get_child_count() < texts.size():
		var label := Label.new()
		var is_name := row.get_child_count() == 0
		label.custom_minimum_size.x = NAME_WIDTH if is_name else CELL_WIDTH
		label.clip_text = true
		label.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_LEFT if is_name else HORIZONTAL_ALIGNMENT_CENTER
		)
		row.add_child(label)
	for i in texts.size():
		(row.get_child(i) as Label).text = texts[i]
