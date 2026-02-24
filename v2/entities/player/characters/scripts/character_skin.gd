@tool
class_name CharacterSkin extends Node3D

@export var skin_definition: CharacterSkinDefinition:
	set(value):
		skin_definition = value
		if Engine.is_editor_hint() and is_node_ready():
			_apply_definition()

@export var ik_controller: IKController
@export var ragdoll_controller: RagdollController

@export_tool_button("Save Markers to resource") var save_markers_btn = _save_markers_to_resource
@export_tool_button("Load Markers from resource") var load_markers_btn = _load_markers_from_resource

@export_tool_button("Save skin to u:disk") var save_skin_btn = _save_skin_to_disk
@export var skin_name_for_loading_test = "biker_default"
@export_tool_button("Load skin from u:disk") var load_skin_btn = _load_skin_to_disk

const HEIGHT: float = 2.0

@onready var anim_player: AnimationPlayer = %AnimationPlayer
@onready var mesh_node: Node3D = %MeshNode

# Accessory markers
@onready var back_marker: Marker3D = %BackAccessoryMarker

var mesh_skin: SkinColor

var skel_3d: Skeleton3D  ## to be used in ik_controller & ragdoll_controller


func _ready():
	_apply_definition()

	ragdoll_controller._create_skeleton_for_ragdoll()
	ik_controller._create_ik()
	if !Engine.is_editor_hint():
		ragdoll_controller.start_ragdoll()


#region resource/definition
func _apply_definition():
	spawn_mesh()
	set_mesh_colors()
	_load_markers_from_resource()
	# Show the biker mesh in the editor
	mesh_skin.owner = self


func _save_skin_to_disk():
	skin_definition.save_to_disk()


func _load_skin_to_disk():
	skin_definition.skin_name = skin_name_for_loading_test
	skin_definition.load_from_disk()


func _load_markers_from_resource():
	back_marker.position = skin_definition.back_marker_position
	back_marker.rotation_degrees = skin_definition.back_marker_rotation_degrees


func _save_markers_to_resource():
	skin_definition.back_marker_position = back_marker.position
	skin_definition.back_marker_rotation_degrees = back_marker.rotation_degrees

	var err = ResourceSaver.save(skin_definition)
	if err == OK:
		print("CharacterSkin: Saved marker positions to ", skin_definition.resource_path)
	else:
		push_error("CharacterSkin: Failed to save resource, error: ", err)


#endregion


#region mesh init
func set_mesh_colors():
	if skin_definition.primary_color != Color.TRANSPARENT:
		mesh_skin.update_primary_color(skin_definition.primary_color)
	if mesh_skin.has_secondary and skin_definition.secondary_color != Color.TRANSPARENT:
		mesh_skin.update_secondary_color(skin_definition.secondary_color)


func spawn_mesh():
	for child in mesh_node.get_children():
		child.queue_free()
	mesh_skin = skin_definition.mesh_res.instantiate()
	mesh_node.add_child(mesh_skin)

	scale_to_height(mesh_skin, HEIGHT)

	# retarget AnimationMixer => Root Node to new mesh
	anim_player.root_node = mesh_skin.get_path()
	anim_player.play("Biker/reset")


#endregion


#region mesh scaling
func scale_to_height(node: Node3D, target_height: float) -> void:
	var aabb := get_combined_aabb(node)
	if aabb.size.y <= 0:
		return
	var scale_factor := target_height / aabb.size.y
	node.scale *= scale_factor


func get_combined_aabb(node: Node3D) -> AABB:
	var combined := AABB()
	var first := true
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_aabb: AABB = child.get_aabb()
			var transformed: AABB = child.transform * mesh_aabb
			if first:
				combined = transformed
				first = false
			else:
				combined = combined.merge(transformed)
		if child is Node3D:
			var child_aabb: AABB = get_combined_aabb(child)
			if child_aabb.size != Vector3.ZERO:
				var transformed: AABB = child.transform * child_aabb
				if first:
					combined = transformed
					first = false
				else:
					combined = combined.merge(transformed)
	return combined


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if skin_definition == null:
		issues.append("skin_definition must be set")
	return issues
