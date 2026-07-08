@tool
class_name EventStartCircle extends Area3D

## Emitted with a reference to *this* circle so consumers can pull
## `gamemode_event` and `get_runners()` off it.
signal entered_event_circle(peer_id: int, event_start_circle: EventStartCircle)
signal exited_event_circle(peer_id: int, event_start_circle: EventStartCircle)

## TODO - show multiple events & be able to select them
@export var gamemode_event: GameModeEventDefinition
## Fill empty grid slots with AI racers for this event. Only used by race
## gamemodes (tutorials and other non-race events leave this off).
@export var enable_npcs: bool = false

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


## Enable/disable every GameModeObject under this circle (checkpoints, killboxes,
## etc.) so an event's props only show + collide while its gamemode is running.
## The circle itself is an Area3D, not a GameModeObject, so its ring/label stay.
func enable_game_objects():
	_set_game_objects_active(self, true)


func disable_game_objects():
	_set_game_objects_active(self, false)


func _set_game_objects_active(node: Node, active: bool):
	for child in node.get_children():
		if child is GameModeObject:
			child.is_active = active
		_set_game_objects_active(child, active)


func _on_body_entered(body: Node3D):
	if !body is PlayerEntity:
		return
	entered_event_circle.emit(int(body.name), self)


func _on_body_exited(body: Node3D):
	if !body is PlayerEntity:
		return
	exited_event_circle.emit(int(body.name), self)
