@tool
## A mesh bolted onto the bike at one of the skin definition's mod markers (authored on
## PlayerEntity's mod markers, which preview every AttachmentMod in the editor).
class_name AttachmentMod extends BikeMod

enum Marker { TRAINING_WHEELS, WHEELIE_BAR }

@export var scene: PackedScene
@export var marker: Marker = Marker.TRAINING_WHEELS
## Also place a copy mirrored across the bike's centerline: model one side, get both.
@export var mirror_x: bool = false

## Mirror across the bike's centerline (X = 0) through this.
const MIRROR_X := Transform3D(Basis.FLIP_X, Vector3.ZERO)


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
	# mesh_node is cleared on every apply_definition, so attachments go with the old mesh.
	_add(vehicle_skin.mesh_node, at)
	if mirror_x:
		_add(vehicle_skin.mesh_node, MIRROR_X * at)


func _add(parent: Node3D, at: Transform3D) -> void:
	var node: Node3D = scene.instantiate()
	node.transform = at
	parent.add_child(node)
