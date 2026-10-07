## Tricks-menu demo, Skate 3 style: loops an authored run (approach, ramp, air, landing) on a
## RiderVisual and fires the trick from the run's `trick_on` / `trick_off` method keys. Runs live in
## DemoAnims and move %Rig. The run for a trick is the first that exists of "<state>_<trick>",
## "<trick>", "<state>" (lowercase, e.g. "air_superman", "backflip", "wheelie"), else FALLBACK_ANIM.
class_name TrickDemo extends Node3D

## Rear-wheel spin on top of the rig's speed, keyed by runs where the rear outspins the road
## (burnout, drift).
@export var rear_wheel_spin: float = 0.0
## Follow cam: offset from the rider, and how far behind the rider (along the run, -Z) it aims. The
## lead puts the rider in the right of the frame, clear of the tricks list.
@export var camera_offset := Vector3(-5.5, 1.6, 0.0)
@export var camera_lead: float = 4.6
## How fast the camera's height catches up with the rider's (jumps).
@export var camera_follow_speed: float = 5.0

const FALLBACK_ANIM := "ground"
## A rig jump this big in one frame is a run looping back to its start, so the camera cuts.
const CAMERA_CUT_DISTANCE := 5.0

@onready var camera: Camera3D = %Camera3D
@onready var _anims: AnimationPlayer = %DemoAnims
@onready var _rig: Node3D = %Rig
@onready var _rider: RiderVisual = %RiderVisual

var _trick: TrickController.Trick = TrickController.Trick.NONE
var _prev_rig_pos: Vector3
var _cam_focus: Vector3


func _process(delta: float) -> void:
	if not _anims.is_playing():
		return
	var rig_pos := _rig.global_position
	var moved := rig_pos.distance_to(_prev_rig_pos)
	_prev_rig_pos = rig_pos
	if moved > CAMERA_CUT_DISTANCE:
		moved = 0.0
		_cam_focus = rig_pos
	# Track the run exactly along the ground (smoothing it lags the rider off-frame at speed); only
	# height eases, so jumps don't jerk the view.
	var follow := clampf(camera_follow_speed * delta, 0.0, 1.0)
	_cam_focus = Vector3(rig_pos.x, lerpf(_cam_focus.y, rig_pos.y, follow), rig_pos.z)
	camera.global_position = _cam_focus + camera_offset
	camera.look_at(_cam_focus + Vector3(0.0, 1.0, -camera_lead))

	var speed := moved / delta
	_rider.bike_skin.rotate_wheels(speed, speed + rear_wheel_spin, delta)
	_rider.update_tricks(delta)


## Seats the active loadout and starts the fallback run, so the scene isn't empty before a hover.
func show_rider(bike_def: BikeSkinDefinition, char_def: CharacterSkinDefinition) -> void:
	_rider.bike_skin.skin_definition = bike_def
	_rider.bike_skin.apply_definition()
	_rider.character_skin.skin_definition = char_def
	_rider.character_skin.apply_definition()
	_rider.seat()
	play(TrickController.Trick.NONE, TrickController.TrickState.NONE)


func play(trick: TrickController.Trick, state: TrickController.TrickState) -> void:
	_rider.stop_tricks()
	_trick = trick
	rear_wheel_spin = 0.0
	# Restarts even when the new trick maps to the run already playing.
	_anims.stop()
	_anims.play(_anim_for(trick, state))
	# Apply the run's first frame now so the camera starts on it.
	_anims.seek(0.0, true)
	_prev_rig_pos = _rig.global_position
	_cam_focus = _prev_rig_pos


## Method-key targets in the runs.
func trick_on() -> void:
	_rider.start_trick(_trick)


func trick_off() -> void:
	_rider.end_trick(_trick)


func _anim_for(trick: TrickController.Trick, state: TrickController.TrickState) -> String:
	var trick_name := TrickController.trick_to_str(trick).to_lower()
	var state_name := String(TrickController.TrickState.keys()[state]).to_lower()
	for anim in [state_name + "_" + trick_name, trick_name, state_name]:
		if _anims.has_animation(anim):
			return anim
	return FALLBACK_ANIM
