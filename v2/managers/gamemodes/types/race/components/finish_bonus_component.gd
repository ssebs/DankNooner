@tool
## Points by finish order among humans (NPCs ignored).
class_name FinishBonusComponent extends RaceComponent

## Score by finish place; 0 past the end.
@export var placement_points: PackedInt32Array = PackedInt32Array([300, 200, 150, 100, 50])

var _finish_order: Array[int] = []


func race_start() -> void:
	_finish_order.clear()


func racer_finished(peer_id: int) -> void:
	_finish_order.append(peer_id)


func score(peer_id: int) -> float:
	var place := _finish_order.find(peer_id)
	if place < 0 or place >= placement_points.size():
		return 0.0
	return placement_points[place]
