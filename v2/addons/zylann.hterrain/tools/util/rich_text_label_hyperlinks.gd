@tool
extends RichTextLabel


func _init() -> void:
	meta_clicked.connect(_on_meta_clicked)


func _on_meta_clicked(meta: Variant) -> void:
	OS.shell_open(meta)
