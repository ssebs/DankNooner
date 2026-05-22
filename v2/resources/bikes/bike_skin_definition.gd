@tool
class_name BikeSkinDefinition extends Resource

## Name of the skin for saving to disk
@export var skin_name: String = "replace_me"

## res:// path of the base bike this customized def was derived from. Tracked so we can
## rebuild on remote peers (who don't have the local user:// .tres) by loading the base
## and reapplying mods. Empty for un-customized base defs (fall back to resource_path).
@export var base_res_path: String = ""

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

@export_group("Collision")
# TODO: use this
@export var collision_shape: Shape3D = preload("res://resources/bikes/hitbox/bike_hitbox.tres")
@export var collision_position_offset: Vector3 = Vector3(0, 0.44, 0)
@export var collision_rotation_offset_degrees: Vector3 = Vector3(90, 0, 0)
@export var collision_scale_multiplier: Vector3 = Vector3.ONE

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
@export var engine_rpm_pitch_curve: Curve = preload("res://resources/bikes/ninja_rpm_pitch_curve.tres")

@export_group("Animation")
## Multiplier for rider lean animation when steering
@export var lean_multiplier: float = 1.0
## Multiplier for rider weight shift animation (forward/back)
@export var weight_shift_multiplier: float = 1.0

@export_group("Gearing")
@export var gear_ratios: Array[float] = [2.92, 2.05, 1.6, 1.46, 1.15, 1.0]
@export var num_gears: int = 6
@export var max_rpm: float = 11000.0
@export var idle_rpm: float = 1000.0
@export var stall_rpm: float = 800.0
@export var power_curve: Curve = preload("res://resources/bikes/power_curve.tres")

@export_group("Physics")
@export var max_speed: float = 88.0
@export var acceleration: float = 12.0
@export var brake_strength: float = 30.0
@export var friction: float = 2.0
@export var engine_brake_strength: float = 12.0
@export var max_lean_angle_deg: float = 50.0
@export var lean_speed: float = 2.6
@export var turn_speed: float = 2.0
## Lean amount vs speed (X=speed%, Y=lean multiplier)
@export var lean_curve: Curve = preload("res://player/bikes/resources/lean_speed_curve.tres")
## Steer responsiveness vs speed (X=speed%, Y=steer multiplier) — bell curve shape
## Low at standstill, peaks ~20mph equiv, tapers at top speed
@export var steer_curve: Curve = preload("res://player/bikes/resources/steer_speed_curve.tres")

@export_group("Tricks")
@export var wheelie_balance_point_deg: float = 70.0
@export var max_wheelie_angle_deg: float = 115.0
@export var max_stoppie_angle_deg: float = 105.0
@export var wheelie_rpm_threshold: float = 0.4
## Half-width of the balance point sweet spot (total range = balance_point ± this)
@export var wheelie_balance_point_width_deg: float = 10.0
@export var rotation_speed: float = 2.0
@export var return_speed: float = 3.0

@export_group("Surfaces")
## How strongly this bike is affected by layer 5 (unstable_collision) surfaces.
## 1.0 = full effect (street bike), 0.0 = ignored (dirtbike). Scales drag, wheelie suppression,
## lean-crash threshold reduction, and front-brake-while-steering lowside trigger.
@export_range(0.0, 1.0, 0.05) var unstable_surface_factor: float = 1.0

const USER_SKIN_DIR: String = "user://skins/"
const SKIN_PFX: String = "bike_skin_"

var max_lean_angle_rad: float:
	get:
		return deg_to_rad(max_lean_angle_deg)


func get_user_save_path() -> String:
	return USER_SKIN_DIR + SKIN_PFX + skin_name.to_snake_case() + ".tres"


func save_to_disk() -> String:
	DirAccess.make_dir_recursive_absolute(USER_SKIN_DIR)
	var path := get_user_save_path()
	var err := ResourceSaver.save(self, path)
	if err == OK:
		# Force the cache to point at this in-memory copy. Without this, subsequent
		# load(path) calls (e.g. from_dict round-trips during lobby sync) return the
		# stale cached version instead of the freshly-saved one.
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
	mesh_res = other.mesh_res
	mesh_position_offset = other.mesh_position_offset
	mesh_rotation_offset_degrees = other.mesh_rotation_offset_degrees
	mesh_scale_multiplier = other.mesh_scale_multiplier
	collision_shape = other.collision_shape
	collision_position_offset = other.collision_position_offset
	collision_rotation_offset_degrees = other.collision_rotation_offset_degrees
	collision_scale_multiplier = other.collision_scale_multiplier
	training_wheels_marker_position = other.training_wheels_marker_position
	training_wheels_marker_rotation_degrees = other.training_wheels_marker_rotation_degrees
	seat_marker_position = other.seat_marker_position
	front_wheel_ground_position = other.front_wheel_ground_position
	rear_wheel_ground_position = other.rear_wheel_ground_position
	rear_wheel_back_position = other.rear_wheel_back_position
	front_wheel_front_position = other.front_wheel_front_position
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
	lean_multiplier = other.lean_multiplier
	weight_shift_multiplier = other.weight_shift_multiplier
	gear_ratios = other.gear_ratios.duplicate()
	num_gears = other.num_gears
	max_rpm = other.max_rpm
	idle_rpm = other.idle_rpm
	stall_rpm = other.stall_rpm
	power_curve = other.power_curve
	max_speed = other.max_speed
	acceleration = other.acceleration
	brake_strength = other.brake_strength
	friction = other.friction
	engine_brake_strength = other.engine_brake_strength
	max_lean_angle_deg = other.max_lean_angle_deg
	lean_speed = other.lean_speed
	turn_speed = other.turn_speed
	lean_curve = other.lean_curve
	steer_curve = other.steer_curve
	wheelie_balance_point_deg = other.wheelie_balance_point_deg
	max_wheelie_angle_deg = other.max_wheelie_angle_deg
	max_stoppie_angle_deg = other.max_stoppie_angle_deg
	wheelie_rpm_threshold = other.wheelie_rpm_threshold
	wheelie_balance_point_width_deg = other.wheelie_balance_point_width_deg
	rotation_speed = other.rotation_speed
	return_speed = other.return_speed
	unstable_surface_factor = other.unstable_surface_factor


#region to/from Dictionary
## Network/save serialization. We deliberately do NOT include `resource_path` because it can
## point at a user:// file that only exists on the local peer. Instead we ship the base
## bike's res:// path + the list of mod res:// paths; remote peers rebuild via from_dict().
func to_dict() -> Dictionary:
	var mod_paths: Array = []
	for mod in mods:
		if mod and mod.resource_path != "":
			mod_paths.append(mod.resource_path)
	var base := base_res_path
	if base == "":
		base = resource_path  # un-customized base def loaded directly from res://
	return {
		"skin_name": skin_name,
		"base_res_path": base,
		"mod_paths": mod_paths,
	}


## Rebuild from a dict. Loads the base bike from res://, applies mods, then caches to
## user://skins/ so future loads (and the editor's "Load skin from u:disk") see it.
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

	var rebuilt_mods: Array[BikeMod] = []
	for mp in dict.get("mod_paths", []):
		if mp == "" or not ResourceLoader.exists(mp):
			continue
		var mod := ResourceLoader.load(mp) as BikeMod
		if mod:
			rebuilt_mods.append(mod)
	mods = rebuilt_mods

	save_to_disk()
#endregion
