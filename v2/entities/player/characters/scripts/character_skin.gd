@tool
class_name CharacterSkin extends Node3D

@export var skin_definition: CharacterSkinDefinition:
	set(value):
		skin_definition = value
		if Engine.is_editor_hint() and is_node_ready():
			_apply_definition()

@export_tool_button("Save Markers to resource") var save_markers_btn = _save_markers_to_resource
@export_tool_button("Load Markers from resource") var load_markers_btn = _load_markers_from_resource

@export_tool_button("Save skin to u:disk") var save_skin_btn = _save_skin_to_disk
@export var skin_name_for_loading_test = "biker_default"
@export_tool_button("Load skin from u:disk") var load_skin_btn = _load_skin_to_disk

const HEIGHT: float = 2.0
const ROOT_BONE_NAME = "Hips"
const JOINT_TYPE_MAP = {
	"CONE": PhysicalBone3D.JOINT_TYPE_CONE,
	"HINGE": PhysicalBone3D.JOINT_TYPE_HINGE,
}

@onready var anim_player: AnimationPlayer = %AnimationPlayer
@onready var mesh_node: Node3D = %MeshNode

# Accessory markers
@onready var back_marker: Marker3D = %BackAccessoryMarker

# IK markers
@onready var ik_left_arm_magnet: Marker3D = %LeftArmMagnet
@onready var ik_left_hand: Marker3D = %LeftHand
@onready var ik_right_arm_magnet: Marker3D = %RightArmMagnet
@onready var ik_right_hand: Marker3D = %RightHand

var mesh_skin: SkinColor

var fabrik_ik: FABRIK3D = FABRIK3D.new()
var skel_3d: Skeleton3D
## Needs to be generated in code, used in ragdoll simulation
var skel_root: PhysicalBoneSimulator3D = PhysicalBoneSimulator3D.new()

## Only Left-side bones need to be defined; Right variants are mirrored automatically
var ragdoll_bone_constraints_base = {
	"Spine": {"type": "CONE", "min_bounds": [-0.5, -0.4, -0.6], "max_bounds": [1, 0.4, 0.6]},
	"Head": {"type": "CONE", "min_bounds": [-0.6, -0.6, -0.3], "max_bounds": [0.35, 0.6, 0.3]},
	"LeftUpperArm": {"type": "CONE", "min_bounds": [-0.3, 1, -0.8], "max_bounds": [1.0, 1, 0.8]},
	"LeftLowerArm": {"type": "CONE", "min_bounds": [-0.1, -2, -2], "max_bounds": [2.5, -0.7, 2]},
	"LeftHand": {"type": "CONE", "min_bounds": [-0.3, 0, -0.3], "max_bounds": [0.5, 3, 0.3]},
	"LeftUpperLeg": {"type": "CONE", "min_bounds": [-0.7, -0.8, 1], "max_bounds": [0.7, 1.2, 1]},
	"LeftLowerLeg": {"type": "HINGE", "min_bounds": [0, 1, 0], "max_bounds": [0, 1, -1.5]},
	"LeftFoot": {"type": "CONE", "min_bounds": [-0.4, 1.5, -1.4], "max_bounds": [0.4, 0.3, 0]},
}

var ragdoll_bone_constraints: Dictionary = {}

var ik_settings_map: Dictionary = {
	"angular_delta_limit": 90,  #deg
	"deterministic": true,
	"settings":
	[
		# Must be in magnet, then end order.
		{
			"target": ik_left_arm_magnet,
			"root_bone_name": "LeftUpperArm",
			"end_bone_name": "LeftLowerArm"
		},
		{"target": ik_left_hand, "root_bone_name": "LeftUpperArm", "end_bone_name": "LeftHand"},
		{
			"target": ik_right_arm_magnet,
			"root_bone_name": "RightUpperArm",
			"end_bone_name": "RightLowerArm"
		},
		{"target": ik_right_hand, "root_bone_name": "RightUpperArm", "end_bone_name": "RightHand"},
	]
}


func _ready():
	_apply_definition()

	_create_skeleton_for_ragdoll()
	if !Engine.is_editor_hint():
		start_ragdoll()


#region ragdoll
func start_ragdoll():
	skel_root.physical_bones_start_simulation()


func stop_ragdoll():
	skel_root.physical_bones_stop_simulation()


func _create_skeleton_for_ragdoll():
	skel_3d = mesh_skin.find_child("Skeleton") as Skeleton3D
	if skel_3d == null:
		printerr("could not find skeleton in mesh_skin")
		return

	_build_ragdoll_constraints()
	skel_3d.add_child(skel_root)
	# show in the editor
	skel_root.owner = mesh_skin
	_populate_skeleton_for_ragdoll()


func _populate_skeleton_for_ragdoll():
	for i in skel_3d.get_bone_count():
		var b_name = skel_3d.get_bone_name(i)

		# Skip bones not in our constraint dict (except root bone)
		var is_root = b_name == ROOT_BONE_NAME
		if not is_root and not ragdoll_bone_constraints.has(b_name):
			continue

		var one_physical_bone: PhysicalBone3D = PhysicalBone3D.new()
		skel_root.add_child(one_physical_bone)
		one_physical_bone.owner = skel_3d.get_parent().get_parent()
		one_physical_bone.bone_name = b_name
		one_physical_bone.collision_layer = 1 << 2  # Layer 3
		one_physical_bone.collision_mask = (1 << 0) | (1 << 2)  # Layers 1 and 3

		var rest_bone: Transform3D = skel_3d.get_bone_global_rest(i)
		one_physical_bone.transform = rest_bone

		var capsule_shape: CapsuleShape3D = CapsuleShape3D.new()
		capsule_shape.height = 0.2
		capsule_shape.radius = 0.2
		var collision_shape: CollisionShape3D = CollisionShape3D.new()
		collision_shape.shape = capsule_shape
		one_physical_bone.add_child(collision_shape)

		# Root bone has no joint constraints
		if is_root:
			one_physical_bone.set_joint_type(PhysicalBone3D.JOINT_TYPE_PIN)
			continue

		# Apply joint type and bounds from constraint dict
		var constraint = ragdoll_bone_constraints[b_name]
		var joint_type = JOINT_TYPE_MAP.get(constraint["type"], PhysicalBone3D.JOINT_TYPE_CONE)
		one_physical_bone.set_joint_type(joint_type)

		var min_bounds: Array = constraint.get("min_bounds", [0, 0, 0])
		one_physical_bone.set_joint_rotation(Vector3(min_bounds[0], min_bounds[1], min_bounds[2]))


func _build_ragdoll_constraints() -> void:
	ragdoll_bone_constraints.clear()
	# Copy base constraints and mirror Left -> Right
	for bone_name in ragdoll_bone_constraints_base:
		ragdoll_bone_constraints[bone_name] = ragdoll_bone_constraints_base[bone_name].duplicate()
		if bone_name.begins_with("Left"):
			var right_name = bone_name.replace("Left", "Right")
			ragdoll_bone_constraints[right_name] = (
				ragdoll_bone_constraints_base[bone_name].duplicate()
			)


#endregion


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
