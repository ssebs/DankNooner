@tool
## NavigationRegion3D whose Bake can leave colliders out by layer. Grass carries the default layer
## on some maps, so the road region's include mask alone would make it driveable road. Each race
## level has a road region (racing line) and a costlier grass region (dodges, rejoin paths).
## Needs a navigation_mesh.
class_name NPCNavRegion extends NavigationRegion3D

@export_tool_button("Bake") var bake_btn = bake
## A collider carrying any of these is left out, even if it matches the mesh's collision mask.
@export_flags_3d_physics var exclude_layers: int = 0


func bake() -> void:
	var excluded: Dictionary[Node, int] = {}
	for node in _source_nodes():
		if (node is CollisionObject3D or node is CSGShape3D) and node.collision_layer & exclude_layers:
			excluded[node] = node.collision_layer
	# The parser only has an include mask, so hide excluded colliders from it for the parse
	for node in excluded:
		node.collision_layer = 0
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navigation_mesh, source, self)
	for node in excluded:
		node.collision_layer = excluded[node]

	NavigationServer3D.bake_from_source_geometry_data(navigation_mesh, source)
	DebugUtils.DebugMsg("%s: baked, %d colliders excluded" % [name, excluded.size()])
	# Looked up by name: the EditorInterface identifier doesn't exist in exported builds
	Engine.get_singleton("EditorInterface").mark_scene_as_unsaved()


## Every node the parser may read: the source group's roots (or this region) and all below them.
func _source_nodes() -> Array[Node]:
	var roots: Array[Node] = [self]
	if navigation_mesh.geometry_source_geometry_mode != NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN:
		roots = get_tree().get_nodes_in_group(navigation_mesh.geometry_source_group_name)
	var nodes: Array[Node] = []
	for root in roots:
		nodes.append(root)
		nodes.append_array(root.find_children("*", "", true, false))
	return nodes


func _get_configuration_warnings() -> PackedStringArray:
	var issues := PackedStringArray()
	if navigation_mesh == null:
		issues.append("navigation_mesh must not be empty")
	return issues
