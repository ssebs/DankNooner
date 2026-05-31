@tool
## A track control point. Its transform IS the path data: position = where the
## track goes, the marker's ROLL = banking (the Track reads basis.y as up).
## Each point also owns the config for the segment from THIS point to the NEXT.
## Edit in the viewport; the parent Track rebuilds live.
class_name TrackPoint extends Marker3D

## How much this segment (this point → next) curves: 1 = full Catmull-Rom like
## the rest of the track, 0 = a straight chord. Lower values flatten the segment
## toward the chord for straightaways; anything above 0 stays gap-free with the
## neighbouring segments (only exactly 0 can gap).
@export_range(0.0, 1.0) var curviness: float = 1.0:
	set(v):
		curviness = clampf(v, 0.0, 1.0)
		_notify_track()

## Turn this point into a sharp corner: the road runs straight into and out of it,
## joined by a tight arc of `corner_radius` instead of the default rounded
## Catmull-Rom swoop. Use for hairpins / the Corkscrew. An open track's first/last
## point can't be sharp (no incoming/outgoing chord) and is ignored.
@export var sharp: bool = false:
	set(v):
		sharp = v
		_notify_track()

## Centerline radius (m) of the arc at a `sharp` corner. Smaller = tighter.
## Auto-reduced if it won't fit between the neighbouring points.
@export var corner_radius: float = 8.0:
	set(v):
		corner_radius = maxf(0.0, v)
		_notify_track()

@export_group("Left Side")
## Flat strip extending outward from the left road edge (sand/grass/etc),
## inheriting the road's height + banking. Width lerps to the next point's.
@export var left_runoff_width: float = 0.0:
	set(v):
		left_runoff_width = maxf(0.0, v)
		_notify_track()
## Material + collision for the left runoff. Null = use Track defaults.
@export var left_runoff: SurfaceConfig:
	set(v):
		left_runoff = v
		_notify_track()
## Wall at the outer edge of the left runoff (road edge if no runoff). 0 = none.
@export var left_wall_height: float = 0.0:
	set(v):
		left_wall_height = maxf(0.0, v)
		_notify_track()
## Material + collision for the left wall. Null = use Track defaults.
@export var left_wall: SurfaceConfig:
	set(v):
		left_wall = v
		_notify_track()

@export_group("Right Side")
@export var right_runoff_width: float = 0.0:
	set(v):
		right_runoff_width = maxf(0.0, v)
		_notify_track()
@export var right_runoff: SurfaceConfig:
	set(v):
		right_runoff = v
		_notify_track()
@export var right_wall_height: float = 0.0:
	set(v):
		right_wall_height = maxf(0.0, v)
		_notify_track()
@export var right_wall: SurfaceConfig:
	set(v):
		right_wall = v
		_notify_track()


func _enter_tree() -> void:
	# Live banking/position edits in the viewport rebuild the parent Track.
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_notify_track()


func _notify_track() -> void:
	# Duck-typed (not `is Track`) so TrackPoint doesn't reference the Track
	# class_name — a mutual class_name dependency can crash the editor on reload.
	var parent := get_parent()
	if parent and parent.has_method("queue_rebuild"):
		parent.queue_rebuild()
