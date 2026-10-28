@tool
## Leaderboard table: a header row, then one row per racer, best first. Rows slide to their new
## rank on reorder, so they're placed by hand rather than in a container (which would snap them).
## A score-like cell pops when it climbs; your row punches when you move up a place (HUDFlash).
## Fed by RidingHUDState (live) and ResultsHUDState.
class_name RaceLeaderboard extends Control

## Cell font size; 0 keeps the theme's Label size.
@export var font_size: int = 0

## Row step as a multiple of the font size — the font's own line height is too loose.
const ROW_HEIGHT_SCALE: float = 1.3
## Columns size to their widest text; the name column never shrinks below this.
const NAME_MIN_WIDTH: float = 60.0
const CELL_PADDING: float = 12.0
## Duration of the slide to a new rank.
const REORDER_SECS: float = 0.35
## Column headers are labels, so dim.
const HEADER_ALPHA: float = 0.6

var _header: HBoxContainer = null
## peer_id -> row, and the rank each row last slid to.
var _rows: Dictionary[int, HBoxContainer] = {}
var _ranks: Dictionary[int, int] = {}
## Your rank on the full board last refresh; -1 while you're not on it.
var _own_rank: int = -1


## rows: [{"peer_id": int, "cells": PackedStringArray}], already sorted best-first.
## cells line up with headers (name first).
func set_board(headers: PackedStringArray, rows: Array) -> void:
	if _header == null:
		_header = _add_row()
		_header.modulate.a = HEADER_ALPHA
	_set_cells(_header, headers)

	var own_id := multiplayer.get_unique_id()
	var own_rank := rows.find_custom(func(r): return r["peer_id"] == own_id)
	var rank_up := _own_rank >= 0 and own_rank >= 0 and own_rank < _own_rank
	_own_rank = own_rank

	var live: Dictionary[int, bool] = {}
	for rank in rows.size():
		var peer_id: int = rows[rank]["peer_id"]
		live[peer_id] = true
		if !_rows.has(peer_id):
			var row := _add_row()
			row.position.y = _rank_y(rank)
			_rows[peer_id] = row
			_ranks[peer_id] = rank
		elif _ranks[peer_id] != rank:
			_ranks[peer_id] = rank
			var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_property(_rows[peer_id], "position:y", _rank_y(rank), REORDER_SECS)
		_set_cells(_rows[peer_id], rows[rank]["cells"], peer_id == own_id)

	for peer_id in _rows.keys():
		if !live.has(peer_id):
			_rows[peer_id].queue_free()
			_rows.erase(peer_id)
			_ranks.erase(peer_id)

	var widths := _column_widths(headers, rows)
	for row: HBoxContainer in [_header] + _rows.values():
		for i in row.get_child_count():
			(row.get_child(i) as Label).custom_minimum_size.x = widths[i]
	var total_width := 0.0
	for w in widths:
		total_width += w
	custom_minimum_size = Vector2(total_width, _rank_y(rows.size()))
	if rank_up:
		HUDFlash.punch(_rows[own_id])


func clear() -> void:
	for child in get_children():
		child.queue_free()
	_header = null
	_rows.clear()
	_ranks.clear()
	_own_rank = -1


func _column_widths(headers: PackedStringArray, rows: Array) -> PackedFloat32Array:
	# The cells' own font: their variation picks it, and it differs per theme.
	var font := (_header.get_child(0) as Label).get_theme_font("font")
	var size := _font_size()
	var widths := PackedFloat32Array()
	for i in headers.size():
		var w := font.get_string_size(headers[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		for row in rows:
			var text: String = row["cells"][i]
			w = maxf(w, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
		widths.append(maxf(w + CELL_PADDING, NAME_MIN_WIDTH if i == 0 else 0.0))
	return widths


func _font_size() -> int:
	return font_size if font_size > 0 else get_theme_font_size("font_size", "Label")


## Header sits at rank -1, so data rank 0 is the second line.
func _rank_y(rank: int) -> float:
	return (rank + 1) * _font_size() * ROW_HEIGHT_SCALE


func _add_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Widths are summed by hand in set_board — no gaps between cells.
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	return row


## Grows/trims the row's labels to match, then sets their text. First column is the (wider) name;
## your own row is blue.
func _set_cells(row: HBoxContainer, texts: PackedStringArray, own: bool = false) -> void:
	while row.get_child_count() > texts.size():
		var extra := row.get_child(row.get_child_count() - 1)
		row.remove_child(extra)
		extra.queue_free()
	while row.get_child_count() < texts.size():
		var label := Label.new()
		var is_name := row.get_child_count() == 0
		label.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_LEFT if is_name else HORIZONTAL_ALIGNMENT_CENTER
		)
		label.add_theme_font_size_override("font_size", _font_size())
		label.theme_type_variation = &"OwnLabel" if own else &"HUDTitleLabel"
		row.add_child(label)
	for i in texts.size():
		var label := row.get_child(i) as Label
		# Only plain integers (scores, knockouts) pop — places slide, and lap clocks tick every refresh.
		if (
			row != _header
			and label.text.is_valid_int()
			and texts[i].is_valid_int()
			and texts[i].to_int() > label.text.to_int()
		):
			HUDFlash.pop(label)
		label.text = texts[i]
