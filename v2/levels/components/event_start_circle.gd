@tool
class_name EventStartCircle extends Area3D

signal entered_event_circle(peer_id: int, gamemode_event: GameModeEvent)
signal exited_event_circle(peer_id: int, gamemode_event: GameModeEvent)

## TODO - show multiple events & be able to select them
@export var gamemode_event: GameModeEvent

@onready var event_label: Label3D = %Label3D


func _ready():
	add_to_group(UtilsConstants.GROUPS["EventCircles"], true)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	event_label.text = tr(gamemode_event.name)


func _on_body_entered(body: Node3D):
	if !body is PlayerEntity:
		return
	# DebugUtils.DebugMsg(body.name + " entered start circle")
	entered_event_circle.emit(int(body.name), gamemode_event)


func _on_body_exited(body: Node3D):
	if !body is PlayerEntity:
		return
	# DebugUtils.DebugMsg(body.name + " exited start circle")
	exited_event_circle.emit(int(body.name), gamemode_event)
