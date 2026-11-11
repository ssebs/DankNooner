@tool
## Simulation tuning shared by every skin of a bike type (mini, naked, sport), so skins of a type
## ride identically. BikeSkinDefinition forwards these as read-only properties.
class_name BikeTypeDefinition extends Resource

@export_group("Collision")
@export var collision_shape: Shape3D = preload("res://resources/bikes/hitbox/bike_hitbox.tres")
@export var collision_position_offset: Vector3 = Vector3(0, 0.44, 0)
@export var collision_rotation_offset_degrees: Vector3 = Vector3(90, 0, 0)
@export var collision_scale_multiplier: Vector3 = Vector3.ONE

@export_group("Gearing")
@export var gear_ratios: Array[float] = [2.92, 2.05, 1.6, 1.25, 1, 0.8]
@export var num_gears: int = 6
@export var max_rpm: float = 11000.0
@export var idle_rpm: float = 1000.0
@export var stall_rpm: float = 800.0
@export var power_curve: Curve = preload("res://resources/bikes/power_curve.tres")
## Seconds of zero drive power after each shift while RPM glides to the new gear.
@export var shift_cut_time: float = 0.15

@export_group("Physics")
@export var max_speed: float = 88.0
@export var acceleration: float = 10.0
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
@export var wheelie_balance_point_width_deg: float = 12.0
@export var rotation_speed: float = 1.75
@export var return_speed: float = 1.25

@export_group("Surfaces")
## How strongly this bike is affected by layer 5 (unstable_collision) surfaces.
## 1.0 = full effect (street bike), 0.0 = ignored (dirtbike). Scales drag, wheelie suppression,
## lean-crash threshold reduction, and front-brake-while-steering lowside trigger.
@export_range(0.0, 1.0, 0.05) var unstable_surface_factor: float = 1.0

var max_lean_angle_rad: float:
	get:
		return deg_to_rad(max_lean_angle_deg)
