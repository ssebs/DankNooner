@tool
class_name EventStartCircle extends Area3D

## Emitted with a reference to *this* circle so consumers can pull
## `gamemode_event` and `get_runners()` off it.
signal entered_event_circle(peer_id: int, event_start_circle: EventStartCircle)
signal exited_event_circle(peer_id: int, event_start_circle: EventStartCircle)

## TODO - show multiple events & be able to select them
@export var gamemode_event: GameModeEventDefinition

@onready var event_label: Label3D = %Label3D


func _ready():
	add_to_group(UtilsConstants.GROUPS["EventCircles"], true)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	event_label.text = tr(gamemode_event.name)


## Runners are children of this circle, in tree order. Other children
## (Marker3D, CheckpointMarker, TriggerZone) are ignored — they're referenced
## by individual tasks via @export.
func get_runners() -> Array[TaskRunner]:
	var out: Array[TaskRunner] = []
	for c in get_children():
		if c is TaskRunner:
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
