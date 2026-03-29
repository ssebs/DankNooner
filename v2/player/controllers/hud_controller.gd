@tool
class_name HUDController extends Control

@export var player_entity: PlayerEntity
@export var movement_controller: MovementController
@export var input_controller: InputController
@export var gearing_controller: GearingController
@export var trick_controller: TrickController
@export var crash_controller: CrashController

@onready var _throttle_label: Label = %HUD_THROTTLE
@onready var _brake_label: Label = %HUD_BRAKE
@onready var _clutch_label: Label = %HUD_CLUTCH
@onready var _speed_label: Label = %HUD_SPEED
@onready var _gear_label: Label = %HUD_GEAR
@onready var _grip_label: Label = %HUD_GRIP_DGR
@onready var _trick_msg: Label = %HUD_TRICK_MSG
@onready var _game_msg: Label = %HUD_GAME_MSG


func _ready():
	if Engine.is_editor_hint():
		return
	# Discrete events via signals
	gearing_controller.gear_changed.connect(_on_gear_changed)
	trick_controller.trick_started.connect(_on_trick_started)
	trick_controller.trick_ended.connect(_on_trick_ended)
	crash_controller.crashed.connect(_on_crashed)
	player_entity.respawned.connect(_on_respawned)

	# Manual inits
	_on_gear_changed(1)


func _process(_delta: float):
	if Engine.is_editor_hint():
		return

	# Poll continuous values directly from controllers
	_throttle_label.text = tr("HUD_THROTTLE") % int(input_controller.nfx_throttle * 100)
	_brake_label.text = (
		tr("HUD_BRAKE_F")
		% [
			int(input_controller.nfx_front_brake * 100),
			int(input_controller.nfx_rear_brake * 100),
		]
	)

	if input_controller.nfx_clutch_held:
		_clutch_label.text = tr("HUD_CLUTCH_IN")
	else:
		_clutch_label.text = tr("HUD_CLUTCH_OUT")

	_speed_label.text = tr("HUD_SPEED") % int(movement_controller.speed)
	_grip_label.text = tr("HUD_GRIP") % int(player_entity.grip_usage * 100)


#region signal handlers
func _on_gear_changed(new_gear: int):
	_gear_label.text = tr("HUD_GEAR") % new_gear


func _on_trick_started(trick_type: TrickController.Trick):
	_trick_msg.text = TrickController.Trick.keys()[trick_type]
	_trick_msg.visible = true


func _on_trick_ended(_trick_type: TrickController.Trick):
	_trick_msg.visible = false


func _on_crashed():
	_game_msg.text = tr("HUD_CRASHED")
	_game_msg.visible = true


func _on_respawned():
	_game_msg.visible = false


#endregion


func show_hud() -> void:
	visible = true


func hide_hud() -> void:
	visible = false


## Called from player_entity.gd's do_respawn
func do_reset():
	_gear_label.text = tr("HUD_GEAR") % 1
	_trick_msg.visible = false
	_game_msg.visible = false


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if player_entity == null:
		issues.append("player_entity must not be empty")
	if movement_controller == null:
		issues.append("movement_controller must not be empty")
	if input_controller == null:
		issues.append("input_controller must not be empty")
	if gearing_controller == null:
		issues.append("gearing_controller must not be empty")
	if trick_controller == null:
		issues.append("trick_controller must not be empty")
	if crash_controller == null:
		issues.append("crash_controller must not be empty")
	return issues
