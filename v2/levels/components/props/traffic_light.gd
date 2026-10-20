@tool
class_name TrafficLight extends Node3D

## Pole showing one approach's light of a LIGHT TrafficIntersection, off the same baked clock the
## traffic gate reads, so it matches what riders obey on every peer. Placed by hand.

## The junction this pole belongs to.
@export var intersection: TrafficIntersection:
	set(v):
		intersection = v
		update_configuration_warnings()
## Whose light this shows: traffic coming FROM this side (in the intersection's basis), so a NORTH
## pole faces north toward it. The lamps face this node's -Z.
@export var slot := TrafficIntersection.Slot.NORTH:
	set(v):
		slot = v
		update_configuration_warnings()

@onready var red_lamp: TrafficLightLamp = %RedLamp
@onready var yellow_lamp: TrafficLightLamp = %YellowLamp
@onready var green_lamp: TrafficLightLamp = %GreenLamp

var _junction: TrafficJunctionData
var _shown := -1


func _ready():
	if Engine.is_editor_hint():
		set_process(false)
		return
	var network: TrafficNetwork = intersection.get_parent()
	# Baked in get_intersections() order
	_junction = network.baked.junctions[network.get_intersections().find(intersection)]


func _process(_delta: float):
	var light := _junction.light(slot, NetworkTime.time)
	if light == _shown:
		return
	_shown = light
	red_lamp.lit = light == TrafficJunctionData.Light.RED
	yellow_lamp.lit = light == TrafficJunctionData.Light.AMBER
	green_lamp.lit = light == TrafficJunctionData.Light.GREEN


func _get_configuration_warnings() -> PackedStringArray:
	var issues := PackedStringArray()
	if intersection == null:
		issues.append("intersection must not be empty")
		return issues
	if intersection.control != TrafficIntersection.ControlType.LIGHT:
		issues.append("intersection's control must be LIGHT")
	if intersection.get_slot_road(slot) == null:
		issues.append("intersection has no road in the %s slot" % TrafficIntersection.Slot.keys()[slot])
	return issues
