@tool
class_name BikeSkinDefinition extends Resource

## Name of the skin for saving to disk
@export var skin_name: String = "replace_me"

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

## SkinSlot colors (use TRANSPARENT to skip a slot)
## See skin_color.gd
@export var colors: Array[Color] = []

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
@export var seat_marker_rotation_degrees: Vector3 = Vector3.ZERO
@export var left_handlebar_marker_position: Vector3 = Vector3.ZERO
@export var left_handlebar_marker_rotation_degrees: Vector3 = Vector3.ZERO
@export var left_peg_marker_position: Vector3 = Vector3.ZERO
@export var left_peg_marker_rotation_degrees: Vector3 = Vector3.ZERO
@export var front_wheel_ground_position: Vector3 = Vector3.ZERO
@export var rear_wheel_ground_position: Vector3 = Vector3.ZERO

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

@export_group("Physics")
@export var max_speed: float = 88.0
@export var acceleration: float = 12.0
@export var brake_strength: float = 40.0
@export var friction: float = 2.0
@export var engine_brake_strength: float = 12.0
@export var max_lean_angle_deg: float = 50.0
@export var lean_speed: float = 6.0
@export var turn_speed: float = 2.0
## Lean amount vs speed (X=speed%, Y=lean multiplier)
@export var lean_curve: Curve = preload("res://player/bikes/resources/lean_speed_curve.tres")
## Steer responsiveness vs speed (X=speed%, Y=steer multiplier) — bell curve shape
## Low at standstill, peaks ~20mph equiv, tapers at top speed
@export var steer_curve: Curve = preload("res://player/bikes/resources/steer_speed_curve.tres")

@export_group("Tricks")
@export var wheelie_balance_point_deg: float = 70.0
@export var max_wheelie_angle_deg: float = 115.0
@export var max_stoppie_angle_deg: float = 85.0
@export var wheelie_rpm_threshold: float = 0.65
## Half-width of the balance point sweet spot (total range = balance_point ± this)
@export var wheelie_balance_point_width_deg: float = 10.0
@export var rotation_speed: float = 2.0
@export var return_speed: float = 3.0

const USER_SKIN_DIR: String = "user://skins/"
const SKIN_PFX: String = "bike_skin_"

var max_lean_angle_rad: float:
	get:
		return deg_to_rad(max_lean_angle_deg)

# TODO- copy save_to_disk, load_from_disk, _copy_from, to/from dict...
