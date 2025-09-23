extends Node

# TODO: load from disk
@export var upgrade_stats: UpgradeStatsRes = preload("res://resources/default_upgrade_stats.tres")

var ui: UI

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

var bonus_time: float:
    set(val):
        bonus_time = clampf(val, 0, 100)
        bonus_time_updated.emit(bonus_time)
signal bonus_time_updated(pct: float)

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

var volume: float:
    set(val):
        volume = val
        volume_updated.emit(val)
signal volume_updated(volume: float)

var money: float:
    set(val):
        money = val
        money_updated.emit(val)
signal money_updated(money: float)

var fuel: float:
    set(val):
        fuel = val
        fuel_updated.emit(val)
signal fuel_updated(fuel: float)


signal notify_ui(msg: String, duration: float) # see ui.gd
signal motorcycle_collision(msg: String) # see obstacle.gd

func _hide_warnings_in_editor():
    notify_ui.emit('this should never show up')
    motorcycle_collision.emit('this should never show up')
