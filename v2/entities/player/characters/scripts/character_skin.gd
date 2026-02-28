@tool
class_name CharacterSkin extends Node3D

@export var skin_definition: CharacterSkinDefinition:
	set(value):
		skin_definition = value
		if Engine.is_editor_hint() and is_node_ready():
			apply_definition()

@export var debug_auto_ragdoll: bool = false

@export_tool_button("Enable IK") var enable_ik_btn = enable_ik
@export_tool_button("Disable IK") var disable_ik_btn = disable_ik
@export_tool_button("Enable Ragdoll") var enable_ragdoll_btn = start_ragdoll
@export_tool_button("Disable Ragdoll") var disable_ragdoll_btn = stop_ragdoll

@export_tool_button("Save Markers to resource") var save_markers_btn = _save_markers_to_resource
@export_tool_button("Load Markers from resource") var load_markers_btn = _load_markers_from_resource

@export_tool_button("Save skin to u:disk") var save_skin_btn = _save_skin_to_disk
@export var skin_name_for_loading_test = "biker_default"
@export_tool_button("Load skin from u:disk") var load_skin_btn = _load_skin_to_disk

const HEIGHT: float = 2.0

@onready var ik_controller: IKController = %IKController
@onready var ragdoll_controller: RagdollController = %RagdollController
@onready var anim_player: AnimationPlayer = %AnimationPlayer
@onready var mesh_node: Node3D = %MeshNode

# Accessory markers
@onready var back_marker: Marker3D = %BackAccessoryMarker

var mesh_skin: SkinColor
var skel_3d: Skeleton3D  ## Used in ik_controller & ragdoll_controller


func _ready():
	apply_definition()


#region public api
func apply_definition():
	_spawn_mesh()
	_set_mesh_colors()
	_load_markers_from_resource()
	# Show the biker mesh in the editor
	mesh_skin.owner = self

	ragdoll_controller._create_skeleton_for_ragdoll()
	ik_controller._create_ik()

	if !Engine.is_editor_hint():
		if debug_auto_ragdoll:
			disable_ik()
			start_ragdoll()


func enable_ik():
	ik_controller.enable_ik()


func disable_ik():
	ik_controller.disable_ik()


func start_ragdoll():
	ragdoll_controller.start_ragdoll()


func stop_ragdoll():
	ragdoll_controller.stop_ragdoll()


#endregion


#region resource/definition
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
func _set_mesh_colors():
	var colors: Array[Color] = skin_definition.colors
	for i in range(colors.size()):
		if colors[i] != Color.TRANSPARENT:
			mesh_skin.update_slot_color(i, colors[i])


func _spawn_mesh():
	for child in mesh_node.get_children():
		child.queue_free()
	mesh_skin = skin_definition.mesh_res.instantiate()
	mesh_node.add_child(mesh_skin)

	_scale_to_height(mesh_skin, HEIGHT)

	# retarget AnimationMixer => Root Node to new mesh
	anim_player.root_node = mesh_skin.get_path()
	anim_player.play("Biker/reset")


#endregion


#region mesh scaling
func _scale_to_height(node: Node3D, target_height: float) -> void:
	var aabb := _get_combined_aabb(node)
	if aabb.size.y <= 0:
		return
	var scale_factor := target_height / aabb.size.y
	node.scale *= scale_factor


func _get_combined_aabb(node: Node3D) -> AABB:
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
			var child_aabb: AABB = _get_combined_aabb(child)
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
	if ik_controller == null:
		issues.append("ik_controller must be set")
	if ragdoll_controller == null:
		issues.append("ragdoll_controller must be set")
	return issues
