@tool
extends EditorContextMenuPlugin

const ICON = preload("res://addons/mixamo_animation_retargeter/icon.png")


func _popup_menu(paths: PackedStringArray) -> void:
	if not _validate_paths(paths):
		return

	add_context_menu_item("Retarget Mixamo Animations", _retarget, ICON)


func _retarget(paths: Array) -> void:
	for path: String in paths:
		if path.get_extension() == "fbx":
			_process_fbx_file(path)


func _validate_paths(paths: Array) -> bool:
	for path: String in paths:
		if path.get_extension() == "fbx":
			return true

	return false


func _process_fbx_file(fbx_path: String) -> void:
	var dir_path: String = fbx_path.get_base_dir()
	print("Exporting animations from ", fbx_path)

	var import_file_path: String = fbx_path + ".import"
	var config := ConfigFile.new()
	var err := config.load(import_file_path)
	if err == OK:
		var subresources: Dictionary = config.get_value("params", "_subresources", {})
		if "nodes" not in subresources:
			subresources["nodes"] = {}
		if "PATH:Skeleton3D" not in subresources["nodes"]:
			subresources["nodes"]["PATH:Skeleton3D"] = {}

		# Update the specific settings for Skeleton3D
		subresources["nodes"]["PATH:Skeleton3D"]["retarget/bone_map"] = load(
			"res://addons/mixamo_animation_retargeter/mixamo_bone_map.tres"
		)
		subresources["nodes"]["PATH:Skeleton3D"]["retarget/bone_renamer/unique_node/skeleton_name"] = "Skeleton"
		subresources["nodes"]["PATH:Skeleton3D"]["retarget/remove_tracks/unmapped_bones"] = true

		# Add or update the animations section
		if not "animations" in subresources:
			subresources["animations"] = {}
		if not "mixamo_com" in subresources["animations"]:
			subresources["animations"]["mixamo_com"] = {}

		# Get the FBX file name and convert it to snake case
		var fbx_file_name = fbx_path.get_file().get_basename()
		var snake_case_name = fbx_file_name.to_snake_case()

		# Create the relative path (already starts with res://)
		var relative_res_path = dir_path.path_join(snake_case_name + ".res")

		# Update the save to file settings for mixamo_com animation
		subresources["animations"]["mixamo_com"]["save_to_file/enabled"] = true
		subresources["animations"]["mixamo_com"]["save_to_file/keep_custom_tracks"] = true
		subresources["animations"]["mixamo_com"]["save_to_file/path"] = relative_res_path
		subresources["animations"]["mixamo_com"]["settings/loop_mode"] = 0

		# Save the updated subresources back to the config
		config.set_value("params", "_subresources", subresources)

		# Save the changes to the .import file
		err = config.save(import_file_path)
		if err == OK:
			print("Import settings updated successfully for ", fbx_path)
			# Trigger reimport immediately after saving
			_trigger_reimport(fbx_path)
		else:
			print("Failed to save import settings for ", fbx_path)
	else:
		print("Failed to load import file for editing: ", fbx_path)


func _trigger_reimport(fbx_path: String) -> void:
	# Trigger reimport of the FBX file
	var file_system = EditorInterface.get_resource_filesystem()
	file_system.reimport_files([fbx_path])
	print("Triggered reimport of FBX file")
