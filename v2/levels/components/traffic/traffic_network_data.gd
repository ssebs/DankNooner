@tool
class_name TrafficNetworkData extends Resource

## Saved by TrafficNetwork's Bake button; runtime traffic reads only this. All references are
## indices.

@export var lanes: Array[TrafficLaneData] = []
@export var junctions: Array[TrafficJunctionData] = []
## TrafficNetworkBaker.source_hash() at bake time; a mismatch means the bake is stale.
@export var source_hash: int
