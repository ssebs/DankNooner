@tool
class_name CurvedRoad extends Node3D

## matches the idx of meshes
@export var sharpness: int = 1:
	set(value):
		sharpness = value
		if is_node_ready():
			_apply_sharpness()
## idx must match int in sharpness
@export var meshes: Dictionary[int, ArrayMesh]

## Scales the whole piece (X = width, Y = height, Z = length).
@export var piece_scale: Vector3 = Vector3.ONE:
	set(value):
		piece_scale = value
		if is_node_ready():
			scale = piece_scale

## Mesh surface material name -> collision_layer bitmask for that surface.
@export var material_layers: Dictionary[StringName, int]:
	set(value):
		material_layers = value
		update_configuration_warnings()
		if is_node_ready():
			_rebuild_collisions()

const GENERATED_COL_PREFIX: String = "SurfaceCol_"

@onready var mesh: MeshInstance3D = %Mesh


func _ready() -> void:
	scale = piece_scale
	_apply_sharpness()


func _apply_sharpness() -> void:
	mesh.mesh = meshes[sharpness]
	update_configuration_warnings()
	_rebuild_collisions()


func _rebuild_collisions() -> void:
	_clear_generated_collisions()

	var source := mesh.mesh as ArrayMesh
	# Bake the mesh transform into the verts so each body sits at the root
	# with an identity transform (avoids scaled collision shapes).
	var mesh_xform := mesh.transform

	# Group surfaces by material so each unique material gets one collision body
	# (the same material can span multiple surfaces in the mesh).
	var surfaces_by_material: Dictionary[StringName, Array] = {}
	for i in source.get_surface_count():
		var mat_name := StringName(source.surface_get_material(i).resource_name)
		if not surfaces_by_material.has(mat_name):
			surfaces_by_material[mat_name] = []
		surfaces_by_material[mat_name].append(i)

	for mat_name in surfaces_by_material:
		# Unmapped materials are reported via _get_configuration_warnings().
		if not material_layers.has(mat_name):
			continue

		var combined := ArrayMesh.new()
		for i in surfaces_by_material[mat_name]:
			var arrays := source.surface_get_arrays(i)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts.size():
				verts[v] = mesh_xform * verts[v]
			arrays[Mesh.ARRAY_VERTEX] = verts
			combined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

		var col := CollisionShape3D.new()
		col.shape = combined.create_trimesh_shape()

		var body := StaticBody3D.new()
		body.name = "%s%s" % [GENERATED_COL_PREFIX, mat_name]
		body.collision_layer = material_layers[mat_name]
		body.add_child(col)
		add_child(body)
		_set_editor_owner(body)
		_set_editor_owner(col)


func _set_editor_owner(node: Node) -> void:
	# Give generated nodes an owner only while this scene is open in the editor
	# so they show in the Scene dock. At runtime they stay owner-less.
	if Engine.is_editor_hint() and self == get_tree().edited_scene_root:
		node.owner = self


func _clear_generated_collisions() -> void:
	for child in get_children():
		if child.name.begins_with(GENERATED_COL_PREFIX):
			child.free()


func _get_surface_material_names() -> PackedStringArray:
	var names: PackedStringArray = []
	var mesh_node := get_node_or_null(^"Mesh") as MeshInstance3D
	# May be null/empty while the scene is still being built in the editor.
	if mesh_node == null or mesh_node.mesh == null:
		return names
	var source := mesh_node.mesh as ArrayMesh
	for i in source.get_surface_count():
		var mat_name := source.surface_get_material(i).resource_name
		if mat_name not in names:
			names.append(mat_name)
	return names


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	var names := _get_surface_material_names()

	var unmapped: PackedStringArray = []
	for mat_name in names:
		if not material_layers.has(StringName(mat_name)):
			unmapped.append(mat_name)

	if not unmapped.is_empty():
		# Print the list so the names can be copied into the material_layers export.
		print("[CurvedRoad] %d surface materials: %s" % [names.size(), ", ".join(names)])
		warnings.append("Surface materials (%d): %s" % [names.size(), ", ".join(names)])
		warnings.append("Unmapped in material_layers: %s" % ", ".join(unmapped))
	return warnings
