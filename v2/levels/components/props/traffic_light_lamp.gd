@tool
class_name TrafficLightLamp extends Node3D

## One lens of a TrafficLight: glows `color` while lit, dark otherwise.

@export var color := Color.RED:
	set(v):
		color = v
		apply_material()
@export var lit := true:
	set(v):
		lit = v
		apply_material()

const LIT_ENERGY := 4.0
const UNLIT_DARKEN := 0.8

static var _material_cache: Dictionary = {}

@onready var meshinstance: MeshInstance3D = %MeshInstance3D


func _ready():
	apply_material()


func apply_material():
	if not is_node_ready():
		return
	meshinstance.set_surface_override_material(0, _get_shared_material(color, lit))


# One per (color, lit) so every lamp shares it — never mutate
static func _get_shared_material(lamp_color: Color, on: bool) -> StandardMaterial3D:
	var key := [lamp_color, on]
	if _material_cache.has(key):
		return _material_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = lamp_color if on else lamp_color.darkened(UNLIT_DARKEN)
	mat.emission_enabled = on
	mat.emission = lamp_color
	mat.emission_energy_multiplier = LIT_ENERGY
	_material_cache[key] = mat
	return mat
