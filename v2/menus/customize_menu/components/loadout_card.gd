@tool
## Single loadout card: 3D thumbnail + name + select button.
## Used in the customize menu's loadout grid.
class_name LoadoutCard extends Control

signal selected(idx: int)

@export var preview_definition: BikeSkinDefinition:
	set(value):
		preview_definition = value
		if is_node_ready():
			thumbnail.skin_definition = value

@onready var thumbnail: Thumbnail3D = %Thumbnail
@onready var name_label: Label = %NameLabel
@onready var select_btn: Button = %SelectBtn

var _idx: int = -1


func _ready() -> void:
	if Engine.is_editor_hint():
		if preview_definition != null:
			thumbnail.skin_definition = preview_definition
		return
	select_btn.pressed.connect(_on_select_pressed)


func populate(def: BikeSkinDefinition, idx: int, is_active: bool, is_selected: bool) -> void:
	_idx = idx
	thumbnail.skin_definition = def
	var label_text := def.skin_name
	if is_active:
		label_text = "[*] " + label_text
	name_label.text = label_text
	select_btn.text = tr("SELECTED_LABEL") if is_selected else tr("SELECT_LABEL")
	select_btn.disabled = is_selected


func _on_select_pressed() -> void:
	selected.emit(_idx)
