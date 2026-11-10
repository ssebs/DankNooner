@tool
## Spawn slots laid out across one side of the road, or all of it. Place it on the road's centre
## line facing the travel direction (-Z): slots fill columns left to right, then rows back along +Z.
## Children: the Marker3D slots, in tree order (spawn_grid.tscn has one per rider). Only their
## positions are laid out, so riders face the grid's -Z.
class_name SpawnGrid extends Node3D

enum RoadSide {FULL, LEFT, RIGHT, }

## Which part of `width` the slots spread across. RIGHT is the right-hand side of the travel direction.
@export var side: RoadSide = RoadSide.RIGHT:
	set(value):
		side = value
		_apply_layout()

## Road width, centred on the grid.
@export var width: float = 16.0:
	set(value):
		width = value
		_apply_layout()

## Narrowest lane one bike gets, so a narrow road gets fewer, deeper columns.
const MIN_LANE_WIDTH: float = 2.0
const ROW_SPACING: float = 4.0


func _ready():
	_apply_layout()


func get_markers() -> Array[Marker3D]:
	var markers: Array[Marker3D] = []
	markers.assign(find_children("*", "Marker3D", false))
	return markers


func _apply_layout():
	if !is_node_ready():
		return
	var span := width if side == RoadSide.FULL else width / 2.0
	var left_edge := 0.0 if side == RoadSide.RIGHT else -width / 2.0
	var markers := get_markers()
	# Fewest rows that fit, then even them out so the lanes fill the whole span.
	var max_columns := clampi(floori(span / MIN_LANE_WIDTH), 1, markers.size())
	var rows := ceili(markers.size() / float(max_columns))
	var columns := ceili(markers.size() / float(rows))
	var lane := span / columns
	for i in markers.size():
		var row := floori(i / float(columns))
		markers[i].position = Vector3(
			left_edge + lane * (i % columns + 0.5), 0, ROW_SPACING * row
		)
