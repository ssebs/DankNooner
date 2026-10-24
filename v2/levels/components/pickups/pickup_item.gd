@tool
## Spawns a pickup's item mesh from its PickupItemDefinition (mirrors CarSkin's definition-driven
## setup) and sizes the pickup's sphere collider + gold ring to the definition's radius. The
## Area3D, sphere collider, MeshNode and StartRing all live in the scene; the spawned item lives
## inside MeshNode.
class_name PickupItem extends Area3D

@export var pickup_item_definition: PickupItemDefinition:
	set(value):
		pickup_item_definition = value
		if Engine.is_editor_hint() and is_node_ready():
			_apply_definition()

const SILHOUETTE_MATERIAL := preload("res://levels/assets/props/silhouette_fill.tres")
## World-look gap between the item's lowest point and the ring.
const RING_GAP := 0.25

@onready var mesh_node: Node3D = %MeshNode
@onready var collishion_shape: CollisionShape3D = %CollisionShape3D
@onready var ring: Node3D = %StartRing
@onready var ring_mesh: MeshInstance3D = %StartRing/MeshInstance3D

var mesh_root: Node3D
## World look: black-filled item (NeonEdges draws its glowing border) resting just above the ring, so
## it reads by shape alone. Thumbnail3D turns it off for the plain item, centered.
var in_world := true


func _ready():
	_apply_definition()


#region resource/definition
func _apply_definition():
	_spawn_mesh()
	_size_ring()
	if Engine.is_editor_hint():
		mesh_root.owner = self


func _spawn_mesh():
	for child in mesh_node.get_children():
		child.queue_free()
	mesh_root = pickup_item_definition.mesh_res.instantiate()
	mesh_node.add_child(mesh_root)
	# Display-only: a held-slot rider passes through the bubble, so its mesh (e.g. the ramp) mustn't collide.
	for node in mesh_root.find_children("*", "CollisionObject3D", true, false):
		var body := node as CollisionObject3D
		body.collision_layer = 0
		body.collision_mask = 0
	if in_world:
		for node in mesh_root.find_children("*", "GeometryInstance3D", true, false):
			(node as GeometryInstance3D).material_override = SILHOUETTE_MATERIAL

	mesh_root.scale *= pickup_item_definition.mesh_scale_multiplier
	mesh_root.rotation_degrees += pickup_item_definition.mesh_rotation_offset_degrees
	# Recenter the mesh's bounds on the collider (position still 0 here), then add the authored offset.
	var bounds := _mesh_bounds()
	mesh_root.position = pickup_item_definition.mesh_position_offset - bounds.get_center()
	# Rest the lowest point RING_GAP above the ring (at -radius), however big the item is scaled.
	if in_world:
		mesh_root.position.y += bounds.size.y / 2.0 - pickup_item_definition.radius + RING_GAP


## The spawned mesh's combined AABB, in MeshNode space. Merges every VisualInstance3D in the
## subtree so any .glb (however its pivot sits) can be auto-centered.
func _mesh_bounds() -> AABB:
	var to_mesh_node := mesh_node.global_transform.affine_inverse()
	var bounds := AABB()
	var found := false
	for node in mesh_root.find_children("*", "VisualInstance3D", true, false):
		var vi := node as VisualInstance3D
		var local_aabb := (to_mesh_node * vi.global_transform) * vi.get_aabb()
		bounds = local_aabb if not found else bounds.merge(local_aabb)
		found = true
	return bounds


## Sphere collider of the definition's radius, with the ring flat at its bottom.
## Fresh shape + a duplicated mesh so instances don't share (and mutate) the scene's sub-resources;
## the shallow duplicate keeps the shared gold material the ring's pulse animation drives.
func _size_ring():
	var radius := pickup_item_definition.radius

	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collishion_shape.shape = sphere

	var torus := ring_mesh.mesh.duplicate() as TorusMesh
	torus.outer_radius = radius
	torus.inner_radius = radius - 0.1
	ring_mesh.mesh = torus
	ring.position.y = -radius


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if pickup_item_definition == null:
		issues.append("pickup_item_definition must be set")
	return issues
