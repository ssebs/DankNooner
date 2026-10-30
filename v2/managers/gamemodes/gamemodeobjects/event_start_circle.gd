@tool
## Level-placed trigger for its GameModeEvent children — entering it opens the event picker in
## free roam. Also owns show/hide of the events' groups (see set_active_event).
##
## Name the circle anything (e.g. after its gas station). Everything under it moves with it.
## Props / Spawns / Checkpoints are plain Node3Ds, linked in the circle's exports:
## [codeblock]
## GasStation1 (EventStartCircle)
## ├ Props
## │ └ RaceWalls        any Node3D group: arrow walls, ramps, ...
## ├ Spawns
## │ └ RaceSpawns       Marker3D children = grid slots, in tree order
## ├ Checkpoints
## │ └ RaceCheckpoints  CheckPointMarker children, in tree order
## └ StuntRace (GameModeEvent)   links props / spawn / checkpoints / pickups / start_zone
##   ├ Pickups          PickupSpawner children
##   ├ StartZone        TriggerZone the drive-to-start leads to
##   └ runners...
## [/codeblock]
## Every group under props / checkpoints is hidden + uncollided except while an event linking it
## runs. Events share a group by linking the same one. Missing links show as editor warnings.
class_name EventStartCircle extends Area3D

## Emitted with a reference to *this* circle so consumers can pull get_events() off it.
signal entered_event_circle(peer_id: int, event_start_circle: EventStartCircle)
signal exited_event_circle(peer_id: int, event_start_circle: EventStartCircle)

## Fuel-up events (fuel_up_first): the station whose FuelUpMinigame pumps riders are assigned to,
## in tree order. Needs at least one pump per rider.
@export var gas_station: Node3D
## Parent of the groups events link as `props`.
@export var props: Node3D
## Parent of the groups events link as `spawn`.
@export var spawns: Node3D
## Parent of the groups events link as `checkpoints`.
@export var checkpoints: Node3D

@onready var event_label: Label3D = %Label3D


func _ready():
	add_to_group(UtilsConstants.GROUPS["EventCircles"], true)
	add_to_group(UtilsConstants.GROUPS["EditorHideable"], true)
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


## Show + collide only `active_event`'s groups; null hides them all (free roam). Hide-all runs
## first so a group shared with the active event ends up shown.
func set_active_event(active_event: GameModeEvent):
	for root in [props, checkpoints]:
		# Tutorial circles have no groups — skip is intentional
		if root != null:
			for group in root.get_children():
				set_group_active(group, false)
	for event in get_events():
		event.set_active(false)
	if active_event != null:
		active_event.set_active(true)


## A hidden prop mustn't be an invisible wall, so collision follows visibility.
func set_group_active(group: Node3D, active: bool):
	group.visible = active
	_set_collision_active(group, active)


## Recurses so nested GameModeObjects and shapes are caught.
func _set_collision_active(node: Node, active: bool):
	if node is GameModeObject:
		node.is_active = active
	elif node is CollisionShape3D:
		node.disabled = not active
	for child in node.get_children():
		_set_collision_active(child, active)


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
	for event in get_events():
		for group in event.props:
			_warn_if_outside(issues, props, "props", event, group)
		_warn_if_outside(issues, spawns, "spawns", event, event.spawn)
		_warn_if_outside(issues, checkpoints, "checkpoints", event, event.checkpoints)
	return issues


func _warn_if_outside(issues: PackedStringArray, root: Node3D, root_name: String, event: GameModeEvent, group: Node3D):
	if group != null and (root == null or not root.is_ancestor_of(group)):
		issues.append("%s links %s — set %s and put the group under it" % [event.name, group.name, root_name])
