@tool
## Level-placed trigger for its GameModeEvent children — entering it opens the event picker in
## free roam. Also owns show/hide of the events' props (see set_active_event).
class_name EventStartCircle extends Area3D

## Emitted with a reference to *this* circle so consumers can pull get_events() off it.
signal entered_event_circle(peer_id: int, event_start_circle: EventStartCircle)
signal exited_event_circle(peer_id: int, event_start_circle: EventStartCircle)

## Fuel-up events (fuel_up_first): the station whose FuelUpMinigame pumps riders are assigned to,
## in tree order. Needs at least one pump per rider.
@export var gas_station: Node3D

@onready var event_label: Label3D = %Label3D


func _ready():
	add_to_group(UtilsConstants.GROUPS["EventCircles"], true)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	var names := PackedStringArray()
	for event in get_events():
		names.append(tr(event.definition.name))
	event_label.text = "\n".join(names)


func get_events() -> Array[GameModeEvent]:
	var out: Array[GameModeEvent] = []
	for c in get_children():
		if c is GameModeEvent:
			out.append(c)
	return out


## Show + collide only `active_event`'s props; null hides them all (free roam). Routes are toggled
## per event; any other GameModeObject under the circle belongs to every event on it. The circle
## itself is an Area3D, not a GameModeObject, so its ring/label stay.
func set_active_event(active_event: GameModeEvent):
	_set_game_objects_active(self, active_event != null)
	for event in get_events():
		if event.route != null:
			event.route.set_active(false)
	if active_event != null and active_event.route != null:
		active_event.route.set_active(true)


func _set_game_objects_active(node: Node, active: bool):
	for child in node.get_children():
		if child is EventRoute:
			continue
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


func _get_configuration_warnings() -> PackedStringArray:
	var issues: PackedStringArray = []
	if get_events().is_empty():
		issues.append("needs at least one GameModeEvent child")
	return issues
