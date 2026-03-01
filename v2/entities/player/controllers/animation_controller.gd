@tool
## Central API for all rider animation - procedural dynamics, polish animations, and tricks.
class_name AnimationController extends Node

signal state_changed(new_state: RiderState)

enum RiderState {
	RIDING,  # Procedural active, IK enabled
	IDLE,  # Procedural paused, playing idle anims
	TRICK,  # IK disabled, skeleton anim playing
	RAGDOLL,  # Everything disabled
}

@export var visual_root: Node3D
@export var character_skin: CharacterSkin
@export var bike_skin: BikeSkin
@export var movement_controller: MovementController
@export var input_controller: InputController

@export_group("Procedural Settings")
@export var idle_timeout: float = 3.0
@export var lean_smoothing: float = 8.0
@export var weight_shift_smoothing: float = 6.0
@export var max_lean_angle: float = 25.0  ## Max lean angle in degrees
@export var max_bike_pitch: float = 30.0  ## Max bike-only pitch in degrees

var current_state: RiderState = RiderState.RIDING:
	set(value):
		if current_state != value:
			current_state = value
			state_changed.emit(value)

#region Internal State
var _base_butt_pos: Vector3
var _base_chest_pos: Vector3
var _base_visual_root_rotation: Vector3
var _idle_timer: float = 0.0
var _current_lean: float = 0.0
var _current_weight_shift: float = 0.0
var _current_bike_pitch: float = 0.0  # Bike-only rotation (wheelie/stoppie)
var _procedural_enabled: bool = true

# Multipliers from bike definition
var _lean_multiplier: float = 1.0
var _weight_shift_multiplier: float = 1.0
#endregion


func _ready():
	if Engine.is_editor_hint():
		return


func _physics_process(delta: float):
	if Engine.is_editor_hint():
		return
	if current_state != RiderState.RIDING:
		return
	if not _procedural_enabled:
		return

	_update_procedural_animation(delta)
	_update_idle_timer(delta)


#region Public API


## Initialize the animation controller. Call after IK targets are set.
func initialize() -> void:
	if character_skin == null or bike_skin == null or visual_root == null:
		printerr("AnimationController: Missing character_skin, bike_skin, or visual_root")
		return

	# Store base positions/rotations for offset calculations
	var ik_ctrl = character_skin.ik_controller
	if ik_ctrl:
		_base_butt_pos = ik_ctrl.butt_pos.position
		_base_chest_pos = ik_ctrl.ik_chest.position

	_base_visual_root_rotation = visual_root.rotation

	# Load multipliers from bike definition
	var bike_def = bike_skin.skin_definition
	if bike_def:
		_lean_multiplier = bike_def.lean_multiplier if "lean_multiplier" in bike_def else 1.0
		_weight_shift_multiplier = (
			bike_def.weight_shift_multiplier if "weight_shift_multiplier" in bike_def else 1.0
		)


## Enable or disable procedural animation
func set_procedural_enabled(enabled: bool) -> void:
	_procedural_enabled = enabled
	if enabled:
		_reset_to_base_positions()


## Set lean amount (-1 to 1, left to right)
func set_lean(amount: float) -> void:
	_current_lean = clamp(amount, -1.0, 1.0)


## Set weight shift amount (-1 to 1, back to forward)
func set_weight_shift(amount: float) -> void:
	_current_weight_shift = clamp(amount, -1.0, 1.0)


## Set bike-only pitch (-1 to 1, stoppie to wheelie)
func set_bike_pitch(amount: float) -> void:
	_current_bike_pitch = clamp(amount, -1.0, 1.0)


## Play an idle animation (fidget, look around, etc.)
func play_idle_animation(anim_name: String) -> void:
	if current_state == RiderState.RAGDOLL:
		return
	_transition_to_idle()
	if character_skin.ik_anim_player:
		character_skin.ik_anim_player.play(anim_name)


## Play landing settle animation
func play_land_settle() -> void:
	if current_state == RiderState.RAGDOLL:
		return
	# TODO: Implement when IK animations are created


## Play a trick animation (full skeleton override)
func play_trick(trick_name: String) -> void:
	if current_state == RiderState.RAGDOLL:
		return
	_transition_to_trick()
	if character_skin.anim_player:
		character_skin.anim_player.play(trick_name)


## Cancel current trick and return to riding
func cancel_trick() -> void:
	if current_state != RiderState.TRICK:
		return
	_transition_to_riding()


## Start ragdoll mode
func start_ragdoll() -> void:
	current_state = RiderState.RAGDOLL
	character_skin.disable_ik()
	character_skin.start_ragdoll()


## Stop ragdoll and return to riding
func stop_ragdoll() -> void:
	character_skin.stop_ragdoll()
	character_skin.enable_ik()
	_reset_to_base_positions()
	current_state = RiderState.RIDING


#endregion

#region State Transitions


func _transition_to_riding() -> void:
	current_state = RiderState.RIDING
	character_skin.enable_ik()
	_procedural_enabled = true


func _transition_to_idle() -> void:
	current_state = RiderState.IDLE
	_procedural_enabled = false


func _transition_to_trick() -> void:
	current_state = RiderState.TRICK
	character_skin.disable_ik()
	_procedural_enabled = false


#endregion

#region Procedural Animation


func _update_procedural_animation(delta: float) -> void:
	if character_skin == null or input_controller == null or movement_controller == null:
		return
	if visual_root == null or bike_skin == null:
		return

	var ik_ctrl = character_skin.ik_controller
	if ik_ctrl == null:
		return

	# Get input values
	var target_lean = input_controller.steer
	var target_weight_shift = input_controller.lean  # Forward/back lean input

	# Smooth the values
	_current_lean = lerp(_current_lean, target_lean, lean_smoothing * delta)
	_current_weight_shift = lerp(
		_current_weight_shift, target_weight_shift, weight_shift_smoothing * delta
	)

	# wheelie stoppie
	# todo: make wheelies use offsets
	visual_root.rotation.x = _current_weight_shift

	# set_bike_pitch(_current_weight_shift)

	# Calculate offsets
	var lean_offset_x = _current_lean * _lean_multiplier * -0.25  # max 0.25m
	var weight_offset_z = _current_weight_shift * _weight_shift_multiplier * 0.1  # Max 10cm

	# Apply butt position - combine lean (x) and weight shift (z)
	ik_ctrl.butt_pos.position = Vector3(
		_base_butt_pos.x + lean_offset_x, _base_butt_pos.y, _base_butt_pos.z + weight_offset_z
	)

	# Rotate chest for visual lean
	var chest_lean = _current_lean * _lean_multiplier * deg_to_rad(15)
	ik_ctrl.ik_chest.rotation.y = chest_lean

	# Apply lean rotation to visual_root (rotates both bike + rider)
	var lean_angle = _current_lean * deg_to_rad(max_lean_angle)
	visual_root.rotation.z = _base_visual_root_rotation.z + lean_angle

	# Apply bike-only pitch (wheelie/stoppie)
	var pitch_angle = _current_bike_pitch * deg_to_rad(max_bike_pitch)
	bike_skin.rotation.x = pitch_angle


func _update_idle_timer(delta: float) -> void:
	# Check if player is mostly stationary
	var is_idle = movement_controller.current_speed < 1.0 and abs(input_controller.steer) < 0.1

	if is_idle:
		_idle_timer += delta
		if _idle_timer >= idle_timeout and current_state == RiderState.RIDING:
			# TODO: Play random idle animation when they exist
			# play_idle_animation("idle_fidget")
			pass
	else:
		_idle_timer = 0.0
		if current_state == RiderState.IDLE:
			_transition_to_riding()


func _reset_to_base_positions() -> void:
	var ik_ctrl = character_skin.ik_controller
	if ik_ctrl:
		ik_ctrl.butt_pos.position = _base_butt_pos
		ik_ctrl.ik_chest.position = _base_chest_pos
		ik_ctrl.ik_chest.rotation = Vector3.ZERO
	if visual_root:
		visual_root.rotation = _base_visual_root_rotation
	if bike_skin:
		bike_skin.rotation.x = 0.0
	_current_lean = 0.0
	_current_weight_shift = 0.0
	_current_bike_pitch = 0.0


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if visual_root == null:
		issues.append("visual_root must be set")
	if character_skin == null:
		issues.append("character_skin must be set")
	if bike_skin == null:
		issues.append("bike_skin must be set")
	if movement_controller == null:
		issues.append("movement_controller must be set")
	if input_controller == null:
		issues.append("input_controller must be set")
	return issues
