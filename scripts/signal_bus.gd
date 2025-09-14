extends Node

var angle_deg: float:
    set(val):
        angle_deg = val
        angle_updated.emit(val)
signal angle_updated(angle_deg: float)

var throttle_input: float:
    set(val):
        throttle_input = clampf(val, 0, 100)
        throttle_updated.emit(throttle_input)
signal throttle_updated(pct: float)

var score: int:
    set(val):
        score = val
        score_updated.emit(val)
signal score_updated(score: int)

var speed: float = 1:
    set(val):
        speed = val
        speed_updated.emit(val)
signal speed_updated(speed: float)

var distance: float:
    set(val):
        distance = val
        distance_updated.emit(val)
signal distance_updated(distance: float)

signal notify_ui(msg: String, duration: float) # see ui.gd
signal motorcycle_collision(msg: String) # see obstacle.gd

func _hide_warnings_in_editor():
    notify_ui.emit('this should never show up')
    motorcycle_collision.emit('this should never show up')
