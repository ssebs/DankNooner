@tool
class_name TrafficJunctionData extends Resource

## One baked TrafficIntersection.

enum Light { GREEN, AMBER, RED }

@export var position: Vector3
@export var control := TrafficIntersection.ControlType.NONE
@export var green_duration: float
@export var amber_duration: float


## LIGHT only: a slot's light at `time`. North/south are green together, then east/west. Pure
## function of NetworkTime.time, so every peer agrees with nothing synced.
func light(slot: int, time: float) -> Light:
	var phase := green_duration + amber_duration
	var t := fmod(time, phase * 2.0)
	# North/south (even slots) run first
	if (slot % 2 == 0) != (t < phase):
		return Light.RED
	return Light.GREEN if fmod(t, phase) < green_duration else Light.AMBER
