@tool
class_name HUDController extends Control

#region export setter values
@export var speed: float = 0.0:
	set(v):
		speed = v
		_update_speed_label()

@export var current_gear: int = 1:
	set(v):
		current_gear = v
		_update_gear_label()

@export var is_stalled: bool = false:
	set(v):
		is_stalled = v
		_update_gear_label()

@export var rpm_ratio: float = 0.0:
	set(v):
		rpm_ratio = v
		_update_rpm_bar()

@export var throttle: float = 0.0:
	set(v):
		throttle = v
		_update_throttle_bar()

@export var clutch_value: float = 0.0:
	set(v):
		clutch_value = v
		_update_clutch_bar()

@export var grip_usage: float = 0.0:
	set(v):
		grip_usage = v
		_update_grip_bar()

@export var last_trick: int = 0:
	set(v):
		last_trick = v
		_update_trick_label()

@export var boost_count: int = 2:
	set(v):
		boost_count = v
		_update_boost_label()

@export var is_boosting: bool = false:
	set(v):
		is_boosting = v
		_update_boost_label()

@export var is_crashed: bool = false:
	set(v):
		is_crashed = v
		_update_speed_label()

#endregion

@onready var _speed_label: Label = %SpeedLabel
@onready var _gear_label: Label = %GearLabel
@onready var _rpm_bar: ProgressBar = %RPMBar
@onready var _throttle_bar: ProgressBar = %ThrottleBar
@onready var _clutch_bar: ProgressBar = %ClutchBar
@onready var _grip_bar: ProgressBar = %GripBar
@onready var _trick_label: Label = %TrickLabel
@onready var _boost_label: Label = %BoostLabel


func show_hud() -> void:
	visible = true


func hide_hud() -> void:
	visible = false


func _update_speed_label() -> void:
	if _speed_label == null:
		return
	if is_crashed:
		_speed_label.text = "CRASHED - Respawning..."
	else:
		_speed_label.text = "Speed: %d" % int(speed)


func _update_gear_label() -> void:
	if _gear_label == null:
		return
	if is_stalled:
		_gear_label.text = "STALLED - Gear: %d" % current_gear
	else:
		_gear_label.text = "Gear: %d" % current_gear


func _update_rpm_bar() -> void:
	if _rpm_bar == null:
		return
	_rpm_bar.value = rpm_ratio
	if rpm_ratio > 0.9:
		_rpm_bar.modulate = Color(1.0, 0.2, 0.2)
	elif rpm_ratio > 0.7:
		_rpm_bar.modulate = Color(1.0, 0.8, 0.2)
	else:
		_rpm_bar.modulate = Color(0.2, 0.6, 1.0)


func _update_throttle_bar() -> void:
	if _throttle_bar == null:
		return
	_throttle_bar.value = throttle
	if throttle > 0.9:
		_throttle_bar.modulate = Color(1.0, 0.2, 0.2)
	else:
		_throttle_bar.modulate = Color(0.2, 0.8, 0.2)


func _update_clutch_bar() -> void:
	if _clutch_bar == null:
		return
	_clutch_bar.value = clutch_value
	_clutch_bar.modulate = Color(0.8, 0.6, 0.2)


func _update_grip_bar() -> void:
	if _grip_bar == null:
		return
	_grip_bar.value = grip_usage
	if grip_usage > 0.8:
		_grip_bar.modulate = Color(1.0, 0.1, 0.1)
	elif grip_usage > 0.5:
		_grip_bar.modulate = Color(1.0, 0.6, 0.0)
	else:
		_grip_bar.modulate = Color(0.2, 0.8, 0.2)


func _update_trick_label() -> void:
	if _trick_label == null:
		return
	# TrickController.Trick enum: 0 = NONE
	if last_trick != 0:
		_trick_label.text = TrickController.Trick.keys()[last_trick]
		_trick_label.visible = true
	else:
		_trick_label.visible = false


func _update_boost_label() -> void:
	if _boost_label == null:
		return
	_boost_label.text = "Boost: %d" % boost_count
	if is_boosting:
		_boost_label.text += " [ACTIVE]"
		_boost_label.modulate = Color(1.0, 0.8, 0.0)
	else:
		_boost_label.modulate = Color.WHITE


## Called from player_entity.gd's do_respawn
func do_reset():
	pass
