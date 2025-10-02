extends Node

# TODO: load from disk
@export var upgrade_stats: UpgradeStatsRes = preload("res://resources/default_upgrade_stats.tres")

var ui: UI
var speed: float = 0.0

signal notify_ui(msg: String, duration: float) # see ui.gd
signal motorcycle_collision(msg: String) # see obstacle.gd

func _hide_warnings_in_editor():
    notify_ui.emit('this should never show up')
    motorcycle_collision.emit('this should never show up')
