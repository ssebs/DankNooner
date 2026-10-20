class_name JunctionState extends RefCounted

## Who's inside one junction, for NPCTrafficState's entry gate. Server-only, one per baked junction.

var network: TrafficNetworkData
# Rider -> turn lane it entered on
var _inside := {}
# STOP: riders stopped at a line, in arrival order
var _arrivals: Array[Node3D] = []


func _init(network_data: TrafficNetworkData):
	network = network_data


func may_enter(turn_lane: int) -> bool:
	var conflicts := network.lanes[turn_lane].conflicts
	for lane in _inside.values():
		if lane in conflicts:
			return false
	return true


## STOP: queues a stopped rider; true once it's first in line.
func arrive(rider: Node3D) -> bool:
	if rider not in _arrivals:
		_arrivals.append(rider)
	return _arrivals[0] == rider


func enter(rider: Node3D, turn_lane: int):
	_arrivals.erase(rider)
	_inside[rider] = turn_lane


func leave(rider: Node3D):
	_arrivals.erase(rider)
	_inside.erase(rider)
