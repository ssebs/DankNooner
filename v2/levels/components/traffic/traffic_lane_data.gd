@tool
class_name TrafficLaneData extends Resource

## One baked lane. Road lanes have junction -1; turn lanes cross a junction's box.

enum TurnDir { LEFT, THROUGH, RIGHT, U_TURN }

@export var points: PackedVector3Array
## Indices into TrafficNetworkData.lanes.
@export var successors: Array[int] = []
@export var junction := -1
## TrafficIntersection.Slot this turn enters from; -1 on road lanes.
@export var entry_slot := -1
## TurnDir; -1 on road lanes.
@export var turn_dir := -1
## Turn lanes in the same junction that can't be occupied at the same time as this one.
@export var conflicts: Array[int] = []
