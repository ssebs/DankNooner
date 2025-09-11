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

signal notify_ui(msg: String) # see ui.gd


func _hide_warnings_in_editor():
    notify_ui.emit('this should never show up')
