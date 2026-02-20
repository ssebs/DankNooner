@tool
extends EditorPlugin

var context_menu_plugin_instance: EditorContextMenuPlugin


func _enter_tree() -> void:
	context_menu_plugin_instance = (
		preload("res://addons/mixamo_animation_retargeter/context_menu.gd").new()
	)
	add_context_menu_plugin(
		EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM, context_menu_plugin_instance
	)
	print("Mixamo Animation Retargeter loaded.")


func _exit_tree() -> void:
	remove_context_menu_plugin(context_menu_plugin_instance)
	print("Mixamo Animation Retargeter unloaded.")
