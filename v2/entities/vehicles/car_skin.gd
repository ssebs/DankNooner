@tool
## "BikeSkin minus the bike" — spawns the mesh, applies mods, spins wheels. No steering proxy,
## no rider pose; the NPC chassis owns motion, this owns looks.
class_name CarSkin extends Node3D

@export var skin_definition: CarSkinDefinition:
	set(value):
		skin_definition = value
		if Engine.is_editor_hint() and is_node_ready():
			_apply_definition()

const WHEEL_SPIN_MULTIPLIER: float = 3.0

@onready var mesh_node: Node3D = %MeshNode

var mesh_skin: SkinColor


func _ready():
	_apply_definition()


## Nothing calls this yet — the NPC animation controller is the intended caller (deferred).
func rotate_wheels(speed: float, delta: float) -> void:
	if mesh_skin == null:
		return
	var spin := -mesh_skin.wheel_rot_axis * speed * WHEEL_SPIN_MULTIPLIER * delta
	for wheel in mesh_skin.wheel_nodes:
		if wheel:
			wheel.rotation += spin


#region resource/definition
func _apply_definition():
	_spawn_mesh()
	_apply_mods()
	if Engine.is_editor_hint():
		mesh_skin.owner = self


func _apply_mods():
	for mod in skin_definition.mods:
		if mod == null:
			continue
		mod.apply(self)


#endregion


#region mesh init
func _spawn_mesh():
	for child in mesh_node.get_children():
		child.queue_free()
	mesh_skin = skin_definition.mesh_res.instantiate()
	mesh_node.add_child(mesh_skin)

	mesh_skin.scale *= skin_definition.mesh_scale_multiplier
	mesh_skin.position += skin_definition.mesh_position_offset
	mesh_skin.rotation_degrees += skin_definition.mesh_rotation_offset_degrees


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if skin_definition == null:
		issues.append("skin_definition must be set")
	return issues
