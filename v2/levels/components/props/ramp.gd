@tool
## A ramp. A trick_spot ramp floats a "BIG AIR" TrickSpotLabel over its lip during events and can
## become a stunt race's bonus ramp (BonusRampComponent).
class_name Ramp extends PathTrack

enum Height { LOW, HIGH }

## LOW drops the curve's last point (the steep lip)
@export var height: Height = Height.HIGH
## Off for the Ramp item (deployable_ramp.tscn, also the pickup's preview mesh): it comes and goes
## mid-race, so it gets no label and is never a bonus ramp.
@export var trick_spot: bool = true

## Metres above the lip the spot label floats.
const LABEL_HEIGHT: float = 4.0

var spot_label: TrickSpotLabel


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return

	if height == Height.LOW:
		# Curve is shared by every instance
		curve = curve.duplicate()
		curve.remove_point(curve.point_count - 1)
	if !trick_spot:
		return
	spot_label = TrickSpotLabel.new("SPOT_BIG_AIR")
	add_child(spot_label)
	spot_label.global_position = lip_position() + Vector3.UP * LABEL_HEIGHT


## The top of the ramp, where riders take off.
func lip_position() -> Vector3:
	return to_global(curve.get_point_position(curve.point_count - 1))
