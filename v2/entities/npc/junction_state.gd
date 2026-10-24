class_name JunctionState extends RefCounted

## Who's inside one junction, for NPCTrafficState's entry gate. Server-only, one per baked junction.

var network: TrafficNetworkData
# Rider -> turn lane it entered on
var _inside := {}
# Riders held at a line -> turn lane they're waiting on, in arrival order
var _arrivals := {}


func _init(network_data: TrafficNetworkData):
	network = network_data


## No conflicting turn is occupied, or waited on by anyone who arrived before `rider`.
func may_enter(rider: Node3D, turn_lane: int) -> bool:
	var conflicts := network.lanes[turn_lane].conflicts
	for lane in _inside.values():
		if lane in conflicts:
			return false
	# First come first served, or a stream of riders claiming ahead starves a crossing turn
	for waiting in _arrivals:
		if waiting == rider:
			break
		if _arrivals[waiting] in conflicts:
			return false
	return true


## Queues a rider held at a line.
func arrive(rider: Node3D, turn_lane: int):
	if not _arrivals.has(rider):
		_arrivals[rider] = turn_lane


func enter(rider: Node3D, turn_lane: int):
	_arrivals.erase(rider)
	_inside[rider] = turn_lane


func leave(rider: Node3D):
	_arrivals.erase(rider)
	_inside.erase(rider)
