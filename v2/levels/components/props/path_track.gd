@tool
class_name PathTrack extends Path3D
## Path3D with CSGPolygon3D children swept along it

@export var width: int = 20:
	set(v):
		width = v
		apply_width()

@export var color_preset: MaterialPresets.Preset = MaterialPresets.Preset.DARK_GRAY:
	set(v):
		color_preset = v
		apply_color()


func _ready() -> void:
	apply_width()
	apply_color()


# Child polygons are rectangles centered on x = 0, so only their x extents change
func apply_width() -> void:
	if not is_node_ready():
		return

	for csg: CSGPolygon3D in find_children("*", "CSGPolygon3D", false):
		var poly := csg.polygon
		for i in poly.size():
			poly[i].x = signf(poly[i].x) * width / 2.0
		csg.polygon = poly


func apply_color() -> void:
	if not is_node_ready():
		return

	# Reuse the .tscn material's texture so the triplanar look is preserved
	for csg: CSGPolygon3D in find_children("*", "CSGPolygon3D", false):
		var existing := csg.material as StandardMaterial3D
		var texture: Texture2D = existing.albedo_texture if existing else null
		csg.material = MaterialPresets.make_material(color_preset, texture)
