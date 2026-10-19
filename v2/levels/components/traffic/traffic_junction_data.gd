@tool
class_name TrafficJunctionData extends Resource

## One baked TrafficIntersection.

@export var position: Vector3
@export var control := TrafficIntersection.ControlType.NONE
@export var green_duration: float
@export var amber_duration: float
