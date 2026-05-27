@tool
## Single character card: 3D thumbnail + name + select button.
## Used in the customize menu's character selection row.
class_name CharacterCard extends Control

signal selected(skin_name: String)

@export var preview_definition: CharacterSkinDefinition:
	set(value):
		preview_definition = value
		if is_node_ready():
			thumbnail.set_skin(Thumbnail3D.Type.CHARACTER, value)

@onready var thumbnail: Thumbnail3D = %Thumbnail
@onready var name_label: Label = %NameLabel
@onready var select_btn: Button = %SelectBtn

var _skin_name: String = ""


func _ready() -> void:
	if Engine.is_editor_hint():
		if preview_definition != null:
			thumbnail.set_skin(Thumbnail3D.Type.CHARACTER, preview_definition)
		return
	select_btn.pressed.connect(_on_select_pressed)


func populate(def: CharacterSkinDefinition, is_selected: bool) -> void:
	_skin_name = def.skin_name
	thumbnail.set_skin(Thumbnail3D.Type.CHARACTER, def)
	name_label.text = def.skin_name
	select_btn.text = tr("SELECTED_LABEL") if is_selected else tr("SELECT_LABEL")
	select_btn.disabled = is_selected


func _on_select_pressed() -> void:
	selected.emit(_skin_name)
