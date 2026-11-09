@tool
class_name RagdollController extends Node3D

@export var char_skin: CharacterSkin

const ROOT_BONE_NAME = "Hips"

## Needs to be generated in code, used in ragdoll simulation
var skel_root: PhysicalBoneSimulator3D = PhysicalBoneSimulator3D.new()

## 6DOF rotation limits in degrees about the bone's own x/y/z, from rest (y runs along the bone, so y is twist).
## Import retargeting gives every skin the same bone axes. Only Left-side bones need to be defined; Right
## variants are mirrored automatically. angular_damp settles light extremities instead of letting them spin.
## Collider: a capsule along the bone to its "end" bone, or "length" when skins lack one. "length" and
## "radius" are fractions of the torso (Spine to Head), so every skin gets the same proportions.
var ragdoll_bone_constraints_base = {
	"Hips": {"radius": 0.25},
	# x: +bend forward, z: +lean right. Chest and neck have no bodies, so this is the whole spine's range.
	"Spine": {
		"end": "Head", "radius": 0.3,
		"min_bounds": [-45, -45, -45], "max_bounds": [90, 45, 45],
	},
	"Head": {
		"length": 0.45, "radius": 0.22, "angular_damp": 1.0,
		"min_bounds": [-35, -40, -30], "max_bounds": [40, 40, 30],
	},
	# x: +lower toward the side, z: +swing forward
	"LeftUpperArm": {
		"end": "LeftLowerArm", "radius": 0.12,
		"min_bounds": [-110, -60, -60], "max_bounds": [100, 60, 130],
	},
	# x: +elbow bend
	"LeftLowerArm": {
		"end": "LeftHand", "radius": 0.11,
		"min_bounds": [0, -45, -5], "max_bounds": [150, 45, 5],
	},
	# x: +fingers down, z: +fingers forward
	"LeftHand": {
		"length": 0.3, "radius": 0.08, "angular_damp": 1.0,
		"min_bounds": [-50, -10, -20], "max_bounds": [60, 10, 20],
	},
	# x: +swing forward, z: +swing outward
	"LeftUpperLeg": {
		"end": "LeftLowerLeg", "radius": 0.18,
		"min_bounds": [-40, -45, -35], "max_bounds": [130, 45, 75],
	},
	# x: +knee bend
	"LeftLowerLeg": {
		"end": "LeftFoot", "radius": 0.17,
		"min_bounds": [0, -5, -5], "max_bounds": [150, 5, 5],
	},
	# x: +toes up, y: roll, z: toes in/out
	"LeftFoot": {
		"length": 0.45, "radius": 0.09, "angular_damp": 1.0,
		"min_bounds": [-45, -20, -10], "max_bounds": [20, 20, 10],
	},
}

var ragdoll_bone_constraints: Dictionary = {}


func start_ragdoll(launch_impulse: Vector3 = Vector3.ZERO):
	skel_root.physical_bones_start_simulation()
	if launch_impulse != Vector3.ZERO:
		for child in skel_root.get_children():
			if child is PhysicalBone3D:
				child.linear_velocity = launch_impulse


func stop_ragdoll():
	skel_root.physical_bones_stop_simulation()


## Returns global position of the Hips PhysicalBone3D, or Vector3.ZERO if not found
func get_hips_global_position() -> Vector3:
	for child in skel_root.get_children():
		if child is PhysicalBone3D and child.bone_name == ROOT_BONE_NAME:
			return child.global_position
	return Vector3.ZERO


func create_skeleton_for_ragdoll():
	var mesh_skin = char_skin.mesh_skin
	var skel_3d = mesh_skin.find_child("Skeleton") as Skeleton3D
	char_skin.skel_3d = skel_3d
	if skel_3d == null:
		DebugUtils.DebugErrMsg("could not find skeleton in mesh_skin")
		return

	# Clear old skel_root if it exists
	if skel_root != null and is_instance_valid(skel_root):
		skel_root.queue_free()
	skel_root = PhysicalBoneSimulator3D.new()

	_build_ragdoll_constraints()
	skel_3d.add_child(skel_root)
	# show in the editor
	skel_root.owner = mesh_skin
	_populate_skeleton_for_ragdoll()


func _populate_skeleton_for_ragdoll():
	var skel_3d = char_skin.skel_3d
	var spine_pos: Vector3 = skel_3d.get_bone_global_rest(skel_3d.find_bone("Spine")).origin
	var torso: float = spine_pos.distance_to(skel_3d.get_bone_global_rest(skel_3d.find_bone("Head")).origin)
	for i in skel_3d.get_bone_count():
		var b_name = skel_3d.get_bone_name(i)

		if not ragdoll_bone_constraints.has(b_name):
			continue
		var is_root = b_name == ROOT_BONE_NAME
		var constraint: Dictionary = ragdoll_bone_constraints[b_name]

		var one_physical_bone: PhysicalBone3D = PhysicalBone3D.new()
		skel_root.add_child(one_physical_bone)
		one_physical_bone.owner = skel_3d.get_parent().get_parent()
		one_physical_bone.bone_name = b_name
		one_physical_bone.collision_layer = 1 << 2  # Layer 3
		# Layers 1, 3 and traffic, like BikeWreck
		one_physical_bone.collision_mask = (
			(1 << 0) | (1 << 2) | NPCTrafficManager.TRAFFIC_BODY_LAYER_MASK
		)

		var rest_bone: Transform3D = skel_3d.get_bone_global_rest(i)
		one_physical_bone.transform = rest_bone

		var length: float = constraint.get("length", 0.0) * torso
		if constraint.has("end"):
			var end_pos: Vector3 = skel_3d.get_bone_global_rest(skel_3d.find_bone(constraint["end"])).origin
			length = rest_bone.origin.distance_to(end_pos)
		var capsule_shape: CapsuleShape3D = CapsuleShape3D.new()
		capsule_shape.radius = constraint["radius"] * torso
		capsule_shape.height = maxf(length, capsule_shape.radius * 2.0)
		var collision_shape: CollisionShape3D = CollisionShape3D.new()
		collision_shape.shape = capsule_shape
		# Centred along the bone, not on the joint, so gravity swings the limb instead of it holding its pose
		collision_shape.position = Vector3(0, length / 2.0, 0)
		one_physical_bone.add_child(collision_shape)

		# Root bone has no joint constraints
		if is_root:
			one_physical_bone.set_joint_type(PhysicalBone3D.JOINT_TYPE_PIN)
			continue

		one_physical_bone.set_joint_type(PhysicalBone3D.JOINT_TYPE_6DOF)
		for a in 3:
			var axis := "joint_constraints/%s/" % "xyz"[a]
			# Godot inverts 6DOF angular limits: [lower, upper] allows rotation in [-upper, -lower]
			one_physical_bone.set(axis + "angular_limit_lower", -constraint["max_bounds"][a])
			one_physical_bone.set(axis + "angular_limit_upper", -constraint["min_bounds"][a])
		one_physical_bone.angular_damp = constraint.get("angular_damp", 0.0)


func _build_ragdoll_constraints() -> void:
	ragdoll_bone_constraints.clear()
	# Copy base constraints and mirror Left -> Right
	for bone_name in ragdoll_bone_constraints_base:
		var base: Dictionary = ragdoll_bone_constraints_base[bone_name]
		ragdoll_bone_constraints[bone_name] = base.duplicate()
		if bone_name.begins_with("Left"):
			# A Right bone is its mirrored Left with x flipped, so x carries over and y/z negate
			var right: Dictionary = base.duplicate()
			var lo: Array = base["min_bounds"]
			var hi: Array = base["max_bounds"]
			right["min_bounds"] = [lo[0], -hi[1], -hi[2]]
			right["max_bounds"] = [hi[0], -lo[1], -lo[2]]
			if base.has("end"):
				right["end"] = base["end"].replace("Left", "Right")
			ragdoll_bone_constraints[bone_name.replace("Left", "Right")] = right


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if char_skin == null:
		issues.append("char_skin must be set")
	return issues
