@tool
class_name StraightRoad extends Node3D

@export var segments: int = 1:
	set(value):
		segments = maxi(value, 1)
		if is_node_ready():
			_rebuild()

const SEGMENT_LENGTH: float = 10.0
const GENERATED_MESH_PREFIX: String = "MeshSegment_"

@onready var mesh: MeshInstance3D = %Mesh
@onready var right_wall_col: CollisionShape3D = %RightWallCol
@onready var left_wall_col: CollisionShape3D = %LeftWallCol
@onready var ground_col: CollisionShape3D = %GroundCol


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	_clear_generated_meshes()

	# Duplicate the mesh for each extra segment, tiled along +Z.
	for i in range(1, segments):
		var seg := mesh.duplicate() as MeshInstance3D
		seg.name = "%s%d" % [GENERATED_MESH_PREFIX, i]
		seg.unique_name_in_owner = false
		seg.position.z = SEGMENT_LENGTH * i
		add_child(seg)
		# owner stays null so generated copies aren't saved to the scene

	# Lengthen the collision shapes instead of duplicating them, then recenter.
	var total_length := SEGMENT_LENGTH * segments
	var center_z := SEGMENT_LENGTH * 0.5 * (segments - 1)

	var cylinder := right_wall_col.shape as CylinderShape3D  # shared res
	cylinder.height = total_length
	right_wall_col.position.z = center_z
	left_wall_col.position.z = center_z

	var box := ground_col.shape as BoxShape3D
	box.size.z = total_length
	ground_col.position.z = center_z


func _clear_generated_meshes() -> void:
	for child in get_children():
		if child.name.begins_with(GENERATED_MESH_PREFIX):
			child.free()
