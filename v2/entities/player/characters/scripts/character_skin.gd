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

const HEIGHT: float = 1.65

@onready var ik_controller: IKController = %IKController
@onready var ragdoll_controller: RagdollController = %RagdollController
@onready var anim_player: AnimationPlayer = %AnimationPlayer
@onready var ik_anim_player: AnimationPlayer = %IKAnimationPlayer
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

	# NOTE - only do this when testing, uncomment else you'll get invalid owner
	# # Show the biker mesh in the editor
	# mesh_skin.owner = self

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


func set_ik_targets_for_bike(
	seat_marker_position: Vector3, left_handlebar_marker: Vector3, left_peg_marker: Vector3
) -> void:
	# Set seat position (butt)
	ik_controller.butt_pos.position = seat_marker_position

	# Set hand positions - mirror right side by negating x
	ik_controller.ik_left_hand.position = left_handlebar_marker
	ik_controller.ik_right_hand.position = Vector3(
		-left_handlebar_marker.x, left_handlebar_marker.y, left_handlebar_marker.z
	)

	# Set foot positions - mirror right side by negating x
	ik_controller.ik_left_foot.position = left_peg_marker
	ik_controller.ik_right_foot.position = Vector3(
		-left_peg_marker.x, left_peg_marker.y, left_peg_marker.z
	)

	# Set head position above hands (centered x, +0.2m in y)
	ik_controller.ik_head.position = Vector3(
		0.0, seat_marker_position.y + 1, seat_marker_position.z - 0.2
	)


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


func _scale_to_height(node: Node3D, target_height: float) -> void:
	var aabb: AABB = UtilsMesh.get_combined_aabb(node)
	if aabb.size.y <= 0:
		return
	var scale_factor := target_height / aabb.size.y
	node.scale *= scale_factor


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
