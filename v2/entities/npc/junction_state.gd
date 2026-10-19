class_name JunctionState extends RefCounted

## Who's inside one junction, for NPCTrafficState's entry gate. Server-only, one per baked junction.

var network: TrafficNetworkData
# Rider -> turn lane it entered on
var _inside := {}


func _init(network_data: TrafficNetworkData):
	network = network_data


func may_enter(turn_lane: int) -> bool:
	var conflicts := network.lanes[turn_lane].conflicts
	for lane in _inside.values():
		if lane in conflicts:
			return false
	return true


func enter(rider: Node3D, turn_lane: int):
	_inside[rider] = turn_lane


func leave(rider: Node3D):
	_inside.erase(rider)
