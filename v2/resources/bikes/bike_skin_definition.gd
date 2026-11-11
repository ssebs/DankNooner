@tool
class_name BikeSkinDefinition extends Resource

## Name of the skin for saving to disk
@export var skin_name: String = "replace_me"

## res:// path of the base bike this customized def was derived from. Tracked so we can
## rebuild on remote peers (who don't have the local user:// .tres) by loading the base
## and reapplying mods. Empty for un-customized base defs (fall back to resource_path).
@export var base_res_path: String = ""

## Garage cost; 0 = owned by default.
@export var price: int = 0
## Rider level needed before it can be bought; 0 = no gate. Owning it skips the gate.
@export var unlock_level: int = 0

## Simulation tuning shared by every skin of this type. Read through the forwarders below.
@export var bike_type: BikeTypeDefinition

@export_group("Mesh")
## The SkinColor scene to instantiate
@export var mesh_res: PackedScene:
	set(value):
		if value:
			var instance = value.instantiate()
			assert(instance is SkinColor, "Wrong scene type!")
			instance.free()
		mesh_res = value
@export var mesh_position_offset: Vector3 = Vector3.ZERO
@export var mesh_rotation_offset_degrees: Vector3 = Vector3.ZERO
@export var mesh_scale_multiplier: Vector3 = Vector3.ONE
## One per unique SkinSlot, applied before mods. Empty = the mesh's own slot colors.
@export var colors: Array[Color] = []

## Marker positions
@export_group("Markers")
# TODO: use this
@export var training_wheels_marker_position: Vector3 = Vector3.ZERO
@export var training_wheels_marker_rotation_degrees: Vector3 = Vector3.ZERO
@export var seat_marker_position: Vector3 = Vector3.ZERO
@export var front_wheel_ground_position: Vector3 = Vector3.ZERO
@export var rear_wheel_ground_position: Vector3 = Vector3.ZERO
@export var rear_wheel_back_position: Vector3 = Vector3.ZERO
@export var front_wheel_front_position: Vector3 = Vector3.ZERO
## Exhaust tip: where flame/backfire VFX spawns and which way it points (per-bike).
@export var exhaust_tip_position: Vector3 = Vector3.ZERO
@export var exhaust_tip_rotation_degrees: Vector3 = Vector3.ZERO
## Headlight: where the spotlight sits and which way it points (per-bike).
@export var headlight_position: Vector3 = Vector3.ZERO
@export var headlight_rotation_degrees: Vector3 = Vector3.ZERO
## Gas cap: where the fuel-up nozzle goes (per-bike).
@export var gas_cap_position: Vector3 = Vector3(0, 0.97512925, 0.1212935)
## Grind spots: the point that rides the rail in belly grinds (rear: smith / feeble, front: willys).
@export var grind_spot_rear_position: Vector3 = Vector3(0, 0.22485137, -0.36395437)
@export var grind_spot_front_position: Vector3 = Vector3(0, 0.18483545, 0.40625262)

@export_group("Rider Pose")
@export var chest_position: Vector3 = Vector3.ZERO
@export var chest_rotation: Vector3 = Vector3.ZERO
@export var head_position: Vector3 = Vector3.ZERO
@export var head_rotation: Vector3 = Vector3.ZERO
@export var left_arm_magnet_position: Vector3 = Vector3.ZERO
@export var right_arm_magnet_position: Vector3 = Vector3.ZERO
# Hand/foot positions are stored in the handlebar/peg PARENT space (same convention as the
# rotation fields below) so they roundtrip through _sync_targets_from_bike(), which applies
# them via hb_parent.global * Transform3D(rot, pos).
@export var left_hand_position: Vector3 = Vector3.ZERO
@export var right_hand_position: Vector3 = Vector3.ZERO
@export var left_hand_rotation: Vector3 = Vector3.ZERO
@export var right_hand_rotation: Vector3 = Vector3.ZERO
@export var left_foot_position: Vector3 = Vector3.ZERO
@export var right_foot_position: Vector3 = Vector3.ZERO
@export var left_foot_rotation: Vector3 = Vector3.ZERO
@export var right_foot_rotation: Vector3 = Vector3.ZERO
@export var left_leg_magnet_position: Vector3 = Vector3.ZERO
@export var right_leg_magnet_position: Vector3 = Vector3.ZERO

@export_group("Mods")
@export var mods: Array[BikeMod] = []

@export_group("Audio")
## Which engine sound this bike plays.
@export var engine_sound_id: AudioManager.EngineSfx = AudioManager.EngineSfx.NINJA500
## Pitch_scale at idle RPM (curve sample = 0).
@export var engine_min_pitch: float = 1.0
## Pitch_scale at max RPM (curve sample = 1).
@export var engine_max_pitch: float = 2.828
## Maps RPM [0..1] to interpolation factor [0..1] between min/max pitch.
@export
var engine_rpm_pitch_curve: Curve = preload("res://resources/bikes/ninja_rpm_pitch_curve.tres")
## Optional: RPM [0..1] → equal-power crossfade position [0..1] between the engine's low
## and high sound layers. Null = linear (crossover centered mid-RPM). Only used by
## two-layer engine sounds (see EngineSoundEvent.high_layer).
@export var engine_blend_curve: Curve

@export_group("Animation")
## Multiplier for rider lean animation when steering
@export var lean_multiplier: float = 1.0
## Multiplier for rider weight shift animation (forward/back)
@export var weight_shift_multiplier: float = 1.0

const USER_SKIN_DIR: String = "user://skins/"
const SKIN_PFX: String = "bike_skin_"

#region bike_type forwarders
var collision_shape: Shape3D:
	get:
		return bike_type.collision_shape
var collision_position_offset: Vector3:
	get:
		return bike_type.collision_position_offset
var collision_rotation_offset_degrees: Vector3:
	get:
		return bike_type.collision_rotation_offset_degrees
var collision_scale_multiplier: Vector3:
	get:
		return bike_type.collision_scale_multiplier
var gear_ratios: Array[float]:
	get:
		return bike_type.gear_ratios
var num_gears: int:
	get:
		return bike_type.num_gears
var max_rpm: float:
	get:
		return bike_type.max_rpm
var idle_rpm: float:
	get:
		return bike_type.idle_rpm
var stall_rpm: float:
	get:
		return bike_type.stall_rpm
var power_curve: Curve:
	get:
		return bike_type.power_curve
var shift_cut_time: float:
	get:
		return bike_type.shift_cut_time
var max_speed: float:
	get:
		return bike_type.max_speed
var acceleration: float:
	get:
		return bike_type.acceleration
var brake_strength: float:
	get:
		return bike_type.brake_strength
var friction: float:
	get:
		return bike_type.friction
var engine_brake_strength: float:
	get:
		return bike_type.engine_brake_strength
var max_lean_angle_deg: float:
	get:
		return bike_type.max_lean_angle_deg
var max_lean_angle_rad: float:
	get:
		return bike_type.max_lean_angle_rad
var lean_speed: float:
	get:
		return bike_type.lean_speed
var turn_speed: float:
	get:
		return bike_type.turn_speed
var lean_curve: Curve:
	get:
		return bike_type.lean_curve
var steer_curve: Curve:
	get:
		return bike_type.steer_curve
var wheelie_balance_point_deg: float:
	get:
		return bike_type.wheelie_balance_point_deg
var max_wheelie_angle_deg: float:
	get:
		return bike_type.max_wheelie_angle_deg
var max_stoppie_angle_deg: float:
	get:
		return bike_type.max_stoppie_angle_deg
var wheelie_rpm_threshold: float:
	get:
		return bike_type.wheelie_rpm_threshold
var wheelie_balance_point_width_deg: float:
	get:
		return bike_type.wheelie_balance_point_width_deg
var rotation_speed: float:
	get:
		return bike_type.rotation_speed
var return_speed: float:
	get:
		return bike_type.return_speed
var unstable_surface_factor: float:
	get:
		return bike_type.unstable_surface_factor
#endregion


func get_user_save_path() -> String:
	return USER_SKIN_DIR + SKIN_PFX + skin_name.to_snake_case() + ".tres"


func save_to_disk() -> String:
	DirAccess.make_dir_recursive_absolute(USER_SKIN_DIR)
	var path := get_user_save_path()
	var err := ResourceSaver.save(self, path)
	if err == OK:
		# Force the cache to point at this in-memory copy. Without this, subsequent
		# load(path) calls return the stale cached version instead of the freshly-saved one.
		take_over_path(path)
		DebugUtils.DebugMsg("BikeSkinDefinition: Saved to %s" % path)
		return path
	push_error("BikeSkinDefinition: Failed to save, error: %d" % err)
	return ""


func load_from_disk() -> bool:
	var path := get_user_save_path()
	if not ResourceLoader.exists(path):
		push_error("BikeSkinDefinition: File not found: %s" % path)
		return false
	var loaded := ResourceLoader.load(path) as BikeSkinDefinition
	if not loaded:
		push_error("BikeSkinDefinition: Failed to load: %s" % path)
		return false
	_copy_from(loaded)
	return true


func _copy_from(other: BikeSkinDefinition) -> void:
	skin_name = other.skin_name
	base_res_path = other.base_res_path
	price = other.price
	unlock_level = other.unlock_level
	bike_type = other.bike_type
	mesh_res = other.mesh_res
	mesh_position_offset = other.mesh_position_offset
	mesh_rotation_offset_degrees = other.mesh_rotation_offset_degrees
	mesh_scale_multiplier = other.mesh_scale_multiplier
	colors = other.colors.duplicate()
	training_wheels_marker_position = other.training_wheels_marker_position
	training_wheels_marker_rotation_degrees = other.training_wheels_marker_rotation_degrees
	seat_marker_position = other.seat_marker_position
	front_wheel_ground_position = other.front_wheel_ground_position
	rear_wheel_ground_position = other.rear_wheel_ground_position
	rear_wheel_back_position = other.rear_wheel_back_position
	front_wheel_front_position = other.front_wheel_front_position
	exhaust_tip_position = other.exhaust_tip_position
	exhaust_tip_rotation_degrees = other.exhaust_tip_rotation_degrees
	headlight_position = other.headlight_position
	headlight_rotation_degrees = other.headlight_rotation_degrees
	gas_cap_position = other.gas_cap_position
	grind_spot_rear_position = other.grind_spot_rear_position
	grind_spot_front_position = other.grind_spot_front_position
	chest_position = other.chest_position
	chest_rotation = other.chest_rotation
	head_position = other.head_position
	head_rotation = other.head_rotation
	left_arm_magnet_position = other.left_arm_magnet_position
	right_arm_magnet_position = other.right_arm_magnet_position
	left_hand_position = other.left_hand_position
	right_hand_position = other.right_hand_position
	left_hand_rotation = other.left_hand_rotation
	right_hand_rotation = other.right_hand_rotation
	left_foot_position = other.left_foot_position
	right_foot_position = other.right_foot_position
	left_foot_rotation = other.left_foot_rotation
	right_foot_rotation = other.right_foot_rotation
	left_leg_magnet_position = other.left_leg_magnet_position
	right_leg_magnet_position = other.right_leg_magnet_position
	mods = other.mods.duplicate()
	engine_sound_id = other.engine_sound_id
	engine_min_pitch = other.engine_min_pitch
	engine_max_pitch = other.engine_max_pitch
	engine_rpm_pitch_curve = other.engine_rpm_pitch_curve
	engine_blend_curve = other.engine_blend_curve
	lean_multiplier = other.lean_multiplier
	weight_shift_multiplier = other.weight_shift_multiplier


## res:// path of the base bike (sport, mini, ...) this def is, or was customized from.
func get_base_path() -> String:
	# Empty on an un-customized base def loaded directly from res://
	return base_res_path if base_res_path != "" else resource_path


#region to/from Dictionary
## Network/save serialization. We deliberately do NOT include `resource_path` because it can
## point at a user:// file that only exists on the local peer. Instead we ship the base
## bike's res:// path + colors + the list of mod res:// paths; remote peers rebuild via from_dict().
func to_dict() -> Dictionary:
	var mod_paths: Array = []
	for mod in mods:
		if mod and mod.resource_path != "":
			mod_paths.append(mod.resource_path)
	var colors_arr: Array = []
	for c in colors:
		colors_arr.append(c.to_html())
	return {
		"skin_name": skin_name,
		"base_res_path": get_base_path(),
		"colors": colors_arr,
		"mod_paths": mod_paths,
	}


## Rebuild from a dict. Loads the base bike from res:// and applies mods. No disk write — this
## runs per player on every lobby sync, on every peer.
func from_dict(dict: Dictionary) -> void:
	const FALLBACK_BASE := "res://resources/bikes/skins/sport_default_skin_definition.tres"
	var base_path: String = dict.get("base_res_path", "")
	var base_def: BikeSkinDefinition = null
	if base_path != "" and ResourceLoader.exists(base_path):
		base_def = ResourceLoader.load(base_path) as BikeSkinDefinition
	if base_def == null:
		base_def = load(FALLBACK_BASE) as BikeSkinDefinition
		base_path = FALLBACK_BASE
	_copy_from(base_def)
	base_res_path = base_path
	skin_name = dict.get("skin_name", base_def.skin_name)
	colors.clear()
	for hex in dict.get("colors", []):
		colors.append(Color.html(hex))

	var rebuilt_mods: Array[BikeMod] = []
	for mp in dict.get("mod_paths", []):
		if mp == "" or not ResourceLoader.exists(mp):
			continue
		var mod := ResourceLoader.load(mp) as BikeMod
		if mod is ColorMod:
			_fold_color_mod(mod)
		elif mod:
			rebuilt_mods.append(mod)
	mods = rebuilt_mods


## Legacy saves painted player bikes with a ColorMod; that's `colors` now. Same pairing as
## SkinColor.update_all_colors.
func _fold_color_mod(mod: ColorMod) -> void:
	if colors.is_empty():
		colors = SkinColor.get_unique_slot_colors(mesh_res)
	if mod.colors.size() == 1:
		colors.fill(mod.colors[0])
		return
	for i in mini(mod.colors.size(), colors.size()):
		colors[i] = mod.colors[i]
#endregion
