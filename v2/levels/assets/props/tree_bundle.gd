@tool
class_name TreeBundle extends Node3D

## Scatters pines on a jittered grid, then drops each tree's mesh base onto the unstable_collision
## layer below the bundle origin; trees over anything else are deleted. Baked in-editor into
## snapped_heights, since generated children aren't saved.

enum Density {DENSE, MID, SPARSE}

@export_tool_button("Snap to Ground") var snap_btn = snap_to_ground
@export_enum("16:16", "32:32", "48:48", "64:64", "96:96", "128:128", "192:192", "256:256") var size := 64:
	set(v):
		size = v
		_rebuild()
## Length along Z as a multiple of size (width along X).
@export_enum("1x1:1", "1x2:2", "1x4:4") var aspect := 1:
	set(v):
		aspect = v
		_rebuild()
@export var density := Density.DENSE:
	set(v):
		density = v
		_rebuild()
@export var layout_seed := 0:
	set(v):
		layout_seed = v
		_rebuild()
## Trunk colliders on every tree; only enable for bundles players can reach.
@export var has_collision := false
@export var snapped_heights: PackedFloat32Array

const PINE := preload("res://levels/assets/props/Pine.glb")
const CELL_SIZE := {Density.DENSE: 8.0, Density.MID: 11.0, Density.SPARSE: 15.0}
const JITTER := 0.4
const RAY_LENGTH := 500.0
# Pine.glb bark is ~0.5 wide; canopy starts ~1.5 up. Tree scale applies on top.
const TRUNK_RADIUS := 0.5
const TRUNK_HEIGHT := 2.0


func _ready():
	_build()
	if Engine.is_editor_hint():
		set_notify_transform(true)
	var trees := get_children()
	# Runtime only: editor colliders would be hit by snap_to_ground rays from overlapping bundles
	var trunk: CylinderShape3D = null
	if has_collision and not Engine.is_editor_hint():
		trunk = CylinderShape3D.new()
		trunk.radius = TRUNK_RADIUS
		trunk.height = TRUNK_HEIGHT
	for i in snapped_heights.size():
		if is_nan(snapped_heights[i]):
			trees[i].free()
		else:
			trees[i].position.y = snapped_heights[i]
			if trunk:
				_add_trunk_collider(trees[i], trunk)


func _notification(what: int):
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		snap_to_ground()


func snap_to_ground():
	_build()
	var space := get_world_3d().direct_space_state
	var heights := PackedFloat32Array()
	for tree: Node3D in get_children():
		var from := Vector3(tree.global_position.x, global_position.y, tree.global_position.z)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * RAY_LENGTH))
		# Only grow on unstable ground, not roads/ramps. NaN marks the tree for deletion on load
		if hit.is_empty() or not hit.collider.collision_layer & MovementController.UNSTABLE_LAYER_MASK:
			heights.append(NAN)
			tree.free()
			continue
		var mesh: MeshInstance3D = tree.find_children("*", "MeshInstance3D")[0]
		var base_y := (mesh.global_transform * mesh.get_aabb()).position.y
		tree.global_position.y += hit.position.y - base_y
		heights.append(tree.position.y)
	snapped_heights = heights


func _add_trunk_collider(tree: Node3D, trunk: CylinderShape3D):
	var body := StaticBody3D.new()
	body.collision_layer = 3 # default + crash_collision, same as cone_staticbody
	var shape := CollisionShape3D.new()
	shape.shape = trunk
	shape.position.y = TRUNK_HEIGHT / 2.0
	body.add_child(shape)
	tree.add_child(body)


func _rebuild():
	if not is_node_ready():
		return
	snap_to_ground()


func _build():
	for child in get_children():
		child.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	var dims := Vector2(size, size * aspect)
	var cells := Vector2i(dims / CELL_SIZE[density])
	var cell := dims / Vector2(cells)
	for x in cells.x:
		for z in cells.y:
			var offset := Vector2(rng.randf_range(-JITTER, JITTER), rng.randf_range(-JITTER, JITTER))
			var pos := (Vector2(x, z) + Vector2(0.5, 0.5) + offset) * cell - dims / 2.0
			var tree: Node3D = PINE.instantiate()
			tree.position = Vector3(pos.x, 0, pos.y)
			tree.rotation.y = rng.randf() * TAU
			tree.scale = Vector3.ONE * rng.randf_range(1.0, 1.75)
			add_child(tree)
