@tool
class_name BikeSkin extends Node3D

@export var skin_definition: BikeSkinDefinition:
	set(value):
		skin_definition = value
		if Engine.is_editor_hint() and is_node_ready():
			_apply_definition()

@export_tool_button("Save Markers to resource") var save_markers_btn = _save_markers_to_resource
@export_tool_button("Load Markers from resource") var load_markers_btn = _load_markers_from_resource

@export_tool_button("Save skin to u:disk") var save_skin_btn = _save_skin_to_disk
@export var skin_name_for_loading_test = "sport_default"
@export_tool_button("Load skin from u:disk") var load_skin_btn = _load_skin_to_disk

const LENGTH: float = 2.0

@onready var anim_player: AnimationPlayer = %AnimationPlayer
@onready var mesh_node: Node3D = %MeshNode

# Accessory markers
@onready var training_wheels_marker: Marker3D = %TrainingWheelsModsMarker

# TODO - save other markers! copy left to right but offset by -1 on x
@onready var seat_marker: Marker3D = $SeatMarker
@onready var left_handlebar_marker: Marker3D = %LeftHandleBarMarker
@onready var left_peg_marker: Marker3D = $LeftPegMarker

var mesh_skin: SkinColor


func _ready():
	_apply_definition()
	# apply scale


#region resource/definition
func _apply_definition():
	_spawn_mesh()
	_set_mesh_colors()
	_load_markers_from_resource()
	# Show the biker mesh in the editor
	mesh_skin.owner = self


func _save_skin_to_disk():
	skin_definition.save_to_disk()


func _load_skin_to_disk():
	skin_definition.skin_name = skin_name_for_loading_test
	skin_definition.load_from_disk()


func _load_markers_from_resource():
	training_wheels_marker.position = skin_definition.training_wheels_marker_position
	training_wheels_marker.rotation_degrees = (
		skin_definition.training_wheels_marker_rotation_degrees
	)


func _save_markers_to_resource():
	skin_definition.training_wheels_marker_position = training_wheels_marker.position
	skin_definition.training_wheels_marker_rotation_degrees = (
		training_wheels_marker.rotation_degrees
	)

	var err = ResourceSaver.save(skin_definition)
	if err == OK:
		print("BikeSkin: Saved marker positions to ", skin_definition.resource_path)
	else:
		push_error("BikeSkin: Failed to save resource, error: ", err)


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

	mesh_skin.scale *= skin_definition.mesh_scale_multiplier

	# # retarget AnimationMixer => Root Node to new mesh
	# anim_player.root_node = mesh_skin.get_path()
	# anim_player.play("Biker/reset")


#endregion


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []
	if skin_definition == null:
		issues.append("skin_definition must be set")
	return issues
