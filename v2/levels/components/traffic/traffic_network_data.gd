@tool
class_name TrafficNetworkData extends Resource

## Saved by TrafficNetwork's Bake button; runtime traffic reads only this. All references are
## indices.

@export var lanes: Array[TrafficLaneData] = []
@export var junctions: Array[TrafficJunctionData] = []
## TrafficNetworkBaker.source_hash() at bake time; a mismatch means the bake is stale.
@export var source_hash: int

# Runtime sampling only, built on first use and never saved
var _curves: Array[Curve3D] = []


func lane_curve(lane: int) -> Curve3D:
	if _curves.is_empty():
		for lane_data in lanes:
			var curve := Curve3D.new()
			# Points are already sampled every TrafficNetworkBaker.SAMPLE_SPACING
			curve.bake_interval = TrafficNetworkBaker.SAMPLE_SPACING / 2.0
			for point in lane_data.points:
				curve.add_point(point)
			_curves.append(curve)
	return _curves[lane]
