@tool
class_name EventStartCircle extends Area3D

## Emitted with a reference to *this* circle so consumers can pull
## `gamemode_event`, `start_marker`, and `get_tasks()` off it.
signal entered_event_circle(peer_id: int, event_start_circle: EventStartCircle)
signal exited_event_circle(peer_id: int, event_start_circle: EventStartCircle)

## TODO - show multiple events & be able to select them
@export var gamemode_event: GameModeEventDefinition
## Where players teleport to when this event's gamemode starts.
@export var start_marker: Marker3D

@onready var event_label: Label3D = %Label3D


func _ready():
	add_to_group(UtilsConstants.GROUPS["EventCircles"], true)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	event_label.text = tr(gamemode_event.name)


## Tasks are children of this circle, in tree order. Other children
## (CheckpointMarker, TriggerZone, Marker3D) are ignored — they're referenced
## by individual tasks via @export trigger.
func get_tasks() -> Array[GameModeTask]:
	var out: Array[GameModeTask] = []
	for c in get_children():
		if c is GameModeTask:
			out.append(c)
	return out


func _on_body_entered(body: Node3D):
	if !body is PlayerEntity:
		return
	entered_event_circle.emit(int(body.name), self)


func _on_body_exited(body: Node3D):
	if !body is PlayerEntity:
		return
	exited_event_circle.emit(int(body.name), self)
