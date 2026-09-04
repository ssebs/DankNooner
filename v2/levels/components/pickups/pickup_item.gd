@tool
## Spawns a pickup's item mesh from its PickupItemDefinition (mirrors CarSkin's definition-driven
## setup) and sizes the pickup's sphere collider + bubble mesh to the definition's radius. The
## Area3D, sphere collider, MeshNode and bubble MeshInstance3D all live in the scene; the spawned
## item lives inside MeshNode.
class_name PickupItem extends Area3D

@export var pickup_item_definition: PickupItemDefinition:
	set(value):
		pickup_item_definition = value
		if Engine.is_editor_hint() and is_node_ready():
			_apply_definition()

@onready var mesh_node: Node3D = %MeshNode
@onready var collishion_shape: CollisionShape3D = %CollisionShape3D
@onready var mesh_instance: MeshInstance3D = %MeshInstance3D

var mesh_root: Node3D


func _ready():
	_apply_definition()


#region resource/definition
func _apply_definition():
	_spawn_mesh()
	_size_bubble()
	if Engine.is_editor_hint():
		mesh_root.owner = self


func _spawn_mesh():
	for child in mesh_node.get_children():
		child.queue_free()
	mesh_root = pickup_item_definition.mesh_res.instantiate()
	mesh_node.add_child(mesh_root)

	mesh_root.scale *= pickup_item_definition.mesh_scale_multiplier
	mesh_root.rotation_degrees += pickup_item_definition.mesh_rotation_offset_degrees
	# Recenter the mesh's bounds on the bubble (position still 0 here), then add the authored offset.
	mesh_root.position = pickup_item_definition.mesh_position_offset - _mesh_bounds_center()


## Center of the spawned mesh's combined AABB, in MeshNode space. Merges every VisualInstance3D
## in the subtree so any .glb (however its pivot sits) can be auto-centered in the bubble.
func _mesh_bounds_center() -> Vector3:
	var to_mesh_node := mesh_node.global_transform.affine_inverse()
	var bounds := AABB()
	var found := false
	for node in mesh_root.find_children("*", "VisualInstance3D", true, false):
		var vi := node as VisualInstance3D
		var local_aabb := (to_mesh_node * vi.global_transform) * vi.get_aabb()
		bounds = local_aabb if not found else bounds.merge(local_aabb)
		found = true
	if not found:
		return Vector3.ZERO
	return bounds.get_center()


## Collider and bubble mesh are both spheres of the definition's radius. Fresh shape + a
## duplicated mesh so instances don't share (and mutate) the scene's sub-resources.
func _size_bubble():
	var radius := pickup_item_definition.radius

	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collishion_shape.shape = sphere

	var bubble := mesh_instance.mesh.duplicate() as SphereMesh
	bubble.radius = radius
	bubble.height = radius * 2.0
	mesh_instance.mesh = bubble


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if pickup_item_definition == null:
		issues.append("pickup_item_definition must be set")
	return issues
