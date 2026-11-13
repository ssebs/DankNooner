## One challenge in the profile card's drop panel: its name over a thin progress line and count.
class_name ChallengeRow extends VBoxContainer

const DONE_MODULATE := Color(1, 1, 1, 0.5)

@onready var _title: Label = %Title
@onready var _bar: ProgressBar = %Bar
@onready var _count: Label = %Count


func show_challenge(title: String, progress: int, target: int) -> void:
	_title.text = title
	_bar.max_value = target
	_bar.value = progress
	_count.text = "%d/%d" % [progress, target]
	if progress >= target:
		modulate = DONE_MODULATE
