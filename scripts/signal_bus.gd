extends Node

var angle_deg: float:
    set(val):
        angle_deg = val
        angle_updated.emit(val)
signal angle_updated(angle_deg: float)

var throttle_input: float:
    set(val):
        throttle_input = val
        throttle_updated.emit(val)
signal throttle_updated(pct: float)

var score: int:
    set(val):
        score = val
        score_updated.emit(val)
signal score_updated(score: int)

var distance: float:
    set(val):
        distance = val
        distance_updated.emit(val)
signal distance_updated(distance: float)

signal notify_ui(msg: String) # see ui.gd


func _hide_warnings_in_editor():
    notify_ui.emit('this should never show up')
