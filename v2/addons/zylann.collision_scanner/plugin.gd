@tool
extends EditorPlugin

const CollisionOverlay = preload("./collision_overlay.tscn")

var _overlay: Control = null


func _enter_tree():
	var parent := _get_3d_viewport_container()
	if parent == null:
		push_warning("Collision Scanner: Could not find 3D viewport container")
		return
	_overlay = CollisionOverlay.instantiate()
	parent.add_child(_overlay)
	parent.move_child(_overlay, 1)


func _exit_tree():
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null


func _handles(_obj: Object) -> bool:
	return true


func _forward_3d_gui_input(camera: Camera3D, _event: InputEvent) -> int:
	if _overlay != null:
		_overlay.set_camera(camera)
	return AFTER_GUI_INPUT_PASS


func _get_3d_viewport_container() -> Control:
	# Get the main screen's 3D editor viewport
	var base := EditorInterface.get_base_control()
	return _find_first_node(base, "Node3DEditorViewport") as Control


static func _find_first_node(node: Node, klass_name: String) -> Node:
	if node.get_class() == klass_name:
		return node
	for child in node.get_children():
		var found_node := _find_first_node(child, klass_name)
		if found_node != null:
			return found_node
	return null
