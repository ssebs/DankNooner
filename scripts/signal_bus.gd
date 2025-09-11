extends Node

var angle_deg: float:
    set(val):
        angle_deg = val
        angle_updated.emit(val)
signal angle_updated(angle_deg: float)

signal notify_ui(msg: String) # see ui.gd
