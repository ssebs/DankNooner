@tool
class_name PathTrack extends Path3D
## Path3D with CSGPolygon3D children swept along it

@export var width: int = 20:
	set(v):
		width = v
		apply_width()


func _ready() -> void:
	apply_width()


# Child polygons are rectangles centered on x = 0, so only their x extents change
func apply_width() -> void:
	if not is_node_ready():
		return

	for csg: CSGPolygon3D in find_children("*", "CSGPolygon3D", false):
		var poly := csg.polygon
		for i in poly.size():
			poly[i].x = signf(poly[i].x) * width / 2.0
		csg.polygon = poly
