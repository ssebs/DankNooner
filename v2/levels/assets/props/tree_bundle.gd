@tool
class_name TreeBundle extends Node3D

## Scatters pines on a jittered grid, then drops each tree's mesh base onto the collision below the
## bundle origin. Baked in-editor into snapped_heights, since generated children aren't saved.

enum Density { DENSE, MID, SPARSE }

@export_tool_button("Snap to Ground") var snap_btn = snap_to_ground
@export_enum("16:16", "32:32", "48:48", "64:64", "96:96", "128:128", "256:256") var size := 64:
	set(v):
		size = v
		_rebuild()
@export var density := Density.DENSE:
	set(v):
		density = v
		_rebuild()
@export var layout_seed := 0:
	set(v):
		layout_seed = v
		_rebuild()
@export var snapped_heights: PackedFloat32Array

const PINE := preload("res://levels/assets/props/Pine.glb")
const CELL_SIZE := {Density.DENSE: 8.0, Density.MID: 11.0, Density.SPARSE: 15.0}
const JITTER := 0.4
const RAY_LENGTH := 500.0


func _ready():
	_build()
	if Engine.is_editor_hint():
		set_notify_transform(true)
	for i in snapped_heights.size():
		(get_child(i) as Node3D).position.y = snapped_heights[i]


func _notification(what: int):
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		snap_to_ground()


func snap_to_ground():
	var space := get_world_3d().direct_space_state
	var heights := PackedFloat32Array()
	for tree: Node3D in get_children():
		var from := Vector3(tree.global_position.x, global_position.y, tree.global_position.z)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * RAY_LENGTH))
		# No ground below is expected mid-drag in the editor — leave the tree where it is
		if not hit.is_empty():
			var mesh: MeshInstance3D = tree.find_children("*", "MeshInstance3D")[0]
			var base_y := (mesh.global_transform * mesh.get_aabb()).position.y
			tree.global_position.y += hit.position.y - base_y
		heights.append(tree.position.y)
	snapped_heights = heights


func _rebuild():
	if not is_node_ready():
		return
	_build()
	snap_to_ground()


func _build():
	for child in get_children():
		child.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	var cells := int(size / CELL_SIZE[density])
	var cell := float(size) / cells
	for x in cells:
		for z in cells:
			var offset := Vector2(rng.randf_range(-JITTER, JITTER), rng.randf_range(-JITTER, JITTER))
			var pos := (Vector2(x, z) + Vector2(0.5, 0.5) + offset) * cell - Vector2.ONE * size / 2.0
			var tree: Node3D = PINE.instantiate()
			tree.position = Vector3(pos.x, 0, pos.y)
			tree.rotation.y = rng.randf() * TAU
			tree.scale = Vector3.ONE * rng.randf_range(1.0, 1.75)
			add_child(tree)
