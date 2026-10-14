@tool
extends PathTrack

enum Height { LOW, HIGH }

## LOW drops the curve's last point (the steep lip)
@export var height: Height = Height.HIGH


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return

	if height == Height.LOW:
		# Curve is shared by every instance
		curve = curve.duplicate()
		curve.remove_point(curve.point_count - 1)
