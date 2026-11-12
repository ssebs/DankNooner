@tool
## NavigationRegion3D whose Bake can leave colliders out by layer. Grass carries the default layer
## on some maps, so the road region's include mask alone would make it driveable road. Each race
## level has a road region (racing line) and a costlier grass region (dodges, rejoin paths).
## Needs a navigation_mesh.
##
## The level's road region (LevelDefinition.npc_nav_region) also bakes one mesh per race event
## (GameModeEvent with checkpoints): its own mesh plus that event's props, which only collide while
## it runs. Each is saved beside the level and set as the event's road_navmesh.
class_name NPCNavRegion extends NavigationRegion3D

@export_tool_button("Bake") var bake_btn = bake
## A collider carrying any of these is left out, even if it matches the mesh's collision mask.
@export_flags_3d_physics var exclude_layers: int = 0

## Holds one race event's props groups while _bake_race_meshes parses them.
const RACE_PROPS_GROUP := &"npc_nav_race_props"


func _ready() -> void:
	# The toolbar's Bake NavigationMesh can't leave exclude_layers out, so redo its bake ours.
	# Ours never emits bake_finished, so this can't loop.
	if Engine.is_editor_hint():
		bake_finished.connect(bake)


func bake() -> void:
	var source := _parse(navigation_mesh, self)
	NavigationServer3D.bake_from_source_geometry_data(navigation_mesh, source)
	DebugUtils.DebugMsg("%s: baked" % name)
	# Untyped level root: LevelDefinition preloads the player scene, which loads this script
	if owner.npc_nav_region == self:
		await _bake_race_meshes(source)
	# Looked up by name: the EditorInterface identifier doesn't exist in exported builds
	Engine.get_singleton("EditorInterface").mark_scene_as_unsaved()


## Swaps in mesh and returns once the nav map has it: paths come back empty until the map syncs.
## Also waits out a level loaded this frame, whose map hasn't synced at all.
func swap_navmesh(mesh: NavigationMesh) -> void:
	var map := get_navigation_map()
	var stale_iteration := 0 if mesh == navigation_mesh else NavigationServer3D.map_get_iteration_id(map)
	navigation_mesh = mesh
	while NavigationServer3D.map_get_iteration_id(map) == stale_iteration:
		await NavigationServer3D.map_changed


## Each race event's mesh: shared_source plus its own props, nobody else's.
func _bake_race_meshes(shared_source: NavigationMeshSourceGeometryData3D) -> void:
	# Props aren't in the source group, so they get one of their own. Parsed from this region as
	# root, since the parser outputs root-local geometry.
	var props_mesh: NavigationMesh = navigation_mesh.duplicate()
	props_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	props_mesh.geometry_source_group_name = RACE_PROPS_GROUP
	for event: GameModeEvent in owner.find_children("*", "GameModeEvent", true, false):
		# Only races have a line to ride
		if event.checkpoints == null:
			continue
		var source := NavigationMeshSourceGeometryData3D.new()
		source.merge(shared_source)
		for group in event.props:
			group.add_to_group(RACE_PROPS_GROUP)
		source.merge(_parse(props_mesh, self))
		for group in event.props:
			group.remove_from_group(RACE_PROPS_GROUP)
		var mesh: NavigationMesh = navigation_mesh.duplicate()
		# Saved to its own file, which one scene uses
		mesh.resource_local_to_scene = false
		NavigationServer3D.bake_from_source_geometry_data(mesh, source)

		# Event names repeat across circles
		var file := "%s_%s_navmesh.res" % [event.get_circle().name.to_snake_case(), event.name.to_snake_case()]
		var path := owner.scene_file_path.get_base_dir().path_join(file)
		var err := ResourceSaver.save(mesh, path)
		if err != OK:
			push_error("%s: saving %s failed: %s" % [name, path, error_string(err)])
		# Evicts the last bake's copy, which the open scene still holds
		mesh.take_over_path(path)
		event.road_navmesh = mesh
		DebugUtils.DebugMsg("%s: baked %s" % [name, file])
		# Each bake stalls the editor; let it redraw (and print this) between them
		await get_tree().process_frame


## mesh's source geometry under root, with colliders on exclude_layers left out.
func _parse(mesh: NavigationMesh, root: Node) -> NavigationMeshSourceGeometryData3D:
	var excluded: Dictionary[Node, int] = {}
	for node in _source_nodes(mesh, root):
		if (node is CollisionObject3D or node is CSGShape3D) and node.collision_layer & exclude_layers:
			excluded[node] = node.collision_layer
	# The parser only has an include mask, so hide excluded colliders from it for the parse
	for node in excluded:
		node.collision_layer = 0
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, root)
	for node in excluded:
		node.collision_layer = excluded[node]
	DebugUtils.DebugMsg("%s: parsed %s, %d colliders excluded" % [name, root.name, excluded.size()])
	return source


## Every node the parser may read for mesh: the source group's roots (or root) and all below them.
func _source_nodes(mesh: NavigationMesh, root: Node) -> Array[Node]:
	var roots: Array[Node] = [root]
	if mesh.geometry_source_geometry_mode != NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN:
		roots = get_tree().get_nodes_in_group(mesh.geometry_source_group_name)
	var nodes: Array[Node] = []
	for node in roots:
		nodes.append(node)
		nodes.append_array(node.find_children("*", "", true, false))
	return nodes


func _get_configuration_warnings() -> PackedStringArray:
	var issues := PackedStringArray()
	if navigation_mesh == null:
		issues.append("navigation_mesh must not be empty")
	return issues
