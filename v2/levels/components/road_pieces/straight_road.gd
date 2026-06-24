@tool
class_name StraightRoad extends Node3D

## Number of segments tiled along +Z (the road's length).
@export var length_segments: int = 1:
	set(value):
		length_segments = maxi(value, 1)
		if is_node_ready():
			_rebuild()

## Number of segments tiled along +X (the road's width), for grids.
@export var width_segments: int = 1:
	set(value):
		width_segments = maxi(value, 1)
		if is_node_ready():
			_rebuild()

## Scales the whole piece (X = width, Y = height, Z = length).
@export var piece_scale: Vector3 = Vector3.ONE:
	set(value):
		piece_scale = value
		if is_node_ready():
			scale = piece_scale

## Adds wall meshes/collisions to the grid's two outer X edges only.
@export var walls: bool = true:
	set(value):
		walls = value
		if is_node_ready():
			_rebuild()

## The flat road surface, tiled across the whole grid.
@export var mesh_without_walls: ArrayMesh:
	set(value):
		mesh_without_walls = value
		update_configuration_warnings()
## A single centered wall, placed along each outer edge (one per length segment).
@export var mesh_wall: ArrayMesh:
	set(value):
		mesh_wall = value
		update_configuration_warnings()

const SEGMENT_LENGTH: float = 10.0
const GENERATED_MESH_PREFIX: String = "MeshSegment_"
const GENERATED_WALL_PREFIX: String = "WallSegment_"

@onready var mesh: MeshInstance3D = %Mesh
@onready var right_wall_col: CollisionShape3D = %RightWallCol
@onready var left_wall_col: CollisionShape3D = %LeftWallCol
@onready var ground_col: CollisionShape3D = %GroundCol


func _ready() -> void:
	scale = piece_scale
	_rebuild()


func _rebuild() -> void:
	_clear_generated_meshes()
	mesh.mesh = mesh_without_walls

	# Tile the road surface into a grid: width_segments along +X, length_segments along +Z.
	for x in range(width_segments):
		for z in range(length_segments):
			if x == 0 and z == 0:
				continue  # the original %Mesh fills this cell
			var seg := mesh.duplicate() as MeshInstance3D
			seg.name = "%s%d_%d" % [GENERATED_MESH_PREFIX, x, z]
			seg.unique_name_in_owner = false
			seg.position.x = SEGMENT_LENGTH * x
			seg.position.z = SEGMENT_LENGTH * z
			add_child(seg)
			# owner stays null so generated copies aren't saved to the scene

	# Resize the collision shapes to span the grid instead of duplicating them, then recenter.
	var total_length := SEGMENT_LENGTH * length_segments
	var total_width := SEGMENT_LENGTH * width_segments
	var center_z := SEGMENT_LENGTH * 0.5 * (length_segments - 1)
	var center_x := SEGMENT_LENGTH * 0.5 * (width_segments - 1)

	# Walls sit just outside the grid's outer X edges and run the full length.
	var right_wall_x := center_x - total_width * 0.5 - 0.5
	var left_wall_x := center_x + total_width * 0.5 + 0.5

	right_wall_col.disabled = not walls
	left_wall_col.disabled = not walls
	if walls:
		_build_wall_edge(right_wall_x)
		_build_wall_edge(left_wall_x)

	var wall_box := right_wall_col.shape as BoxShape3D  # shared res
	wall_box.size.z = total_length
	right_wall_col.position.x = right_wall_x
	right_wall_col.position.z = center_z
	left_wall_col.position.x = left_wall_x
	left_wall_col.position.z = center_z

	var box := ground_col.shape as BoxShape3D
	box.size.x = total_width
	box.size.z = total_length
	ground_col.position.x = center_x
	ground_col.position.z = center_z


# Places one wall mesh per length segment along the outer edge at the given X.
func _build_wall_edge(wall_x: float) -> void:
	for z in range(length_segments):
		var wall := mesh.duplicate() as MeshInstance3D
		wall.mesh = mesh_wall
		wall.name = "%s%d_%d" % [GENERATED_WALL_PREFIX, int(wall_x), z]
		wall.unique_name_in_owner = false
		wall.position.x = wall_x
		wall.position.z = SEGMENT_LENGTH * z
		add_child(wall)
		# owner stays null so generated copies aren't saved to the scene


func _clear_generated_meshes() -> void:
	for child in get_children():
		if (
			child.name.begins_with(GENERATED_MESH_PREFIX)
			or child.name.begins_with(GENERATED_WALL_PREFIX)
		):
			child.free()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if mesh_without_walls == null:
		warnings.append("mesh_without_walls is not assigned.")
	if mesh_wall == null:
		warnings.append("mesh_wall is not assigned.")
	return warnings
