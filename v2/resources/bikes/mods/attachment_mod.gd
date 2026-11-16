@tool
## A mesh bolted onto the bike at one of the skin definition's mod markers (authored on
## PlayerEntity's mod markers, which preview every AttachmentMod in the editor).
class_name AttachmentMod extends BikeMod

enum Marker { TRAINING_WHEELS, WHEELIE_BAR, WINGS }

@export var scene: PackedScene
@export var marker: Marker = Marker.TRAINING_WHEELS
## Also place a copy mirrored across the bike's centerline: model one side, get both.
@export var mirror_x: bool = false

## Mirror across the bike's centerline (X = 0) through this.
const MIRROR_X := Transform3D(Basis.FLIP_X, Vector3.ZERO)
## Glow for bikes without a glow slot.
const DEFAULT_GLOW := preload("res://levels/assets/props/neon_blue.tres")


##override
func apply(vehicle_skin: Node3D) -> void:
	var def: BikeSkinDefinition = vehicle_skin.skin_definition
	var at := Transform3D.IDENTITY
	match marker:
		Marker.TRAINING_WHEELS:
			at = Transform3D(
				Basis.from_euler(def.training_wheels_marker_rotation_degrees * PI / 180.0),
				def.training_wheels_marker_position
			)
		Marker.WHEELIE_BAR:
			at = Transform3D(
				Basis.from_euler(def.wheelie_bar_marker_rotation_degrees * PI / 180.0),
				def.wheelie_bar_marker_position
			)
		Marker.WINGS:
			at = Transform3D(
				Basis.from_euler(def.wings_marker_rotation_degrees * PI / 180.0),
				def.wings_marker_position
			)
	# mesh_node is cleared on every apply_definition, so attachments go with the old mesh.
	_add(vehicle_skin, at)
	if mirror_x:
		_add(vehicle_skin, MIRROR_X * at)


## `scene` with its emissive surfaces wearing the bike's first glow slot (so it follows recolors),
## or DEFAULT_GLOW.
func instantiate_for(vehicle_skin: Node3D) -> Node3D:
	var glow: Material = vehicle_skin.mesh_skin.first_glow_material()
	if glow == null:
		glow = DEFAULT_GLOW
	var node: Node3D = scene.instantiate()
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D"):
		for i in mesh.mesh.get_surface_count():
			var mat := mesh.mesh.surface_get_material(i) as StandardMaterial3D
			if mat != null and mat.emission_enabled:
				mesh.set_surface_override_material(i, glow)
	return node


func _add(vehicle_skin: Node3D, at: Transform3D) -> void:
	var node := instantiate_for(vehicle_skin)
	node.transform = at
	vehicle_skin.mesh_node.add_child(node)
