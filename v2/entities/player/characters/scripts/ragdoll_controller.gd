class_name RagdollController extends Node3D

@export var char_skin: CharacterSkin

const ROOT_BONE_NAME = "Hips"
const JOINT_TYPE_MAP = {
	"CONE": PhysicalBone3D.JOINT_TYPE_CONE,
	"HINGE": PhysicalBone3D.JOINT_TYPE_HINGE,
}

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
