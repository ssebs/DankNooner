@tool
## Meshes that you want to change the skin color should use this script
class_name SkinColor extends Node3D

@export var slots: Array[SkinSlot]
## Meshes corresponding to each slot (must match slots array length)
@export var meshes: Array[MeshInstance3D]


func _ready() -> void:
	for i in range(slots.size()):
		if slots[i] != null and i < meshes.size() and meshes[i] != null:
			slots[i].setup(meshes[i])


func update_slot_color(index: int, color: Color) -> void:
	if index >= 0 and index < slots.size() and slots[index] != null:
		slots[index].update_color(color)


func update_all_colors(colors: Array[Color]) -> void:
	for i in range(mini(colors.size(), slots.size())):
		if slots[i] != null:
			slots[i].update_color(colors[i])


func _get_configuration_warnings() -> PackedStringArray:
	var issues = []

	if slots.is_empty():
		issues.append("At least one SkinSlot is required")
		return issues

	if meshes.size() != slots.size():
		issues.append("meshes array must match slots array length")

	for i in range(slots.size()):
		if slots[i] == null:
			issues.append("Slot %d is null" % i)
		else:
			var slot_issues = slots[i].get_configuration_issues()
			for issue in slot_issues:
				issues.append("Slot %d: %s" % [i, issue])
		if i < meshes.size() and meshes[i] == null:
			issues.append("Mesh %d is null" % i)

	return issues
