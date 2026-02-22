@tool
class_name CharacterSkin extends Node3D

@export var mesh_res: PackedScene:
	set(value):
		if value:
			var instance = value.instantiate()
			assert(instance is SkinColor, "Wrong scene type!")
			instance.free()
		mesh_res = value
@export var primary_color: Color = Color.RED

const HEIGHT: float = 2.0

@onready var anim_player: AnimationPlayer = %AnimationPlayer
@onready var mesh_node: Node3D = %MeshNode

var mesh_skin: SkinColor


func _ready():
	spawn_mesh()
	mesh_skin.update_primary_color(primary_color)


func spawn_mesh():
	for child in mesh_node.get_children():
		child.queue_free()
	mesh_skin = mesh_res.instantiate()
	mesh_node.add_child(mesh_skin)

	scale_to_height(mesh_skin, HEIGHT)

	# retarget AnimationMixer => Root Node to new mesh
	anim_player.root_node = mesh_skin.get_path()
	anim_player.play("Biker/reset")


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

	if mesh_res == null:
		issues.append("mesh_res must not be empty, and must be a SkinColor")

	return issues
