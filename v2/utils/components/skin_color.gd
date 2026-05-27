@tool
## Meshes that you want to change the skin color should use this script
## Also houses metadata
class_name SkinColor extends Node3D

## A single SkinSlot may appear here multiple times — each position binds it to the mesh at
## the same index, and a color update propagates to every position that references it.
@export var slots: Array[SkinSlot]
## Meshes corresponding to each slot (must match slots length)
@export var meshes: Array[MeshInstance3D]

@export_category("BikeSpecifics")
@export var steering_rotation_node: Node3D
@export var front_wheel_node: Node3D
@export var rear_wheel_node: Node3D
@export var steering_rot_axis: Vector3 = Vector3.UP
@export var wheel_rot_axis: Vector3 = Vector3.RIGHT

# Per slot-position runtime materials. Owned by this instance so nothing leaks across other
# SkinColor instances that share the same SkinSlot resource.
var _runtime_materials: Array[Material] = []


func _ready() -> void:
	_runtime_materials.resize(slots.size())
	for i in range(slots.size()):
		var slot := slots[i]
		if slot == null or i >= meshes.size() or meshes[i] == null:
			continue
		var mat := slot.make_runtime_material()
		if mat == null:
			continue
		meshes[i].set_surface_override_material(slot.surface_index, mat)
		_runtime_materials[i] = mat
		slot.apply_color_to(mat, slot.color)


## Update a single slot's color. If the slot at `index` appears at multiple positions in
## `slots`, every position's material is updated — that's how one SkinSlot drives N meshes.
func update_slot_color(index: int, color: Color) -> void:
	if index < 0 or index >= slots.size() or slots[index] == null:
		return
	_apply_color_to_all_materials_for(slots[index], color)


## Apply a list of colors to the slot palette.
## - 1 color: broadcast to every unique slot (single-color mod paints every mesh).
## - N colors: pair colors[i] → i-th UNIQUE slot, truncated to min(colors, unique_slots).
##   This way a 2-color mod on a bike with one shared slot uses only colors[0].
func update_all_colors(colors: Array[Color]) -> void:
	if colors.is_empty():
		return
	var unique_slots := _unique_slots()
	if colors.size() == 1:
		for slot in unique_slots:
			_apply_color_to_all_materials_for(slot, colors[0])
		return
	for i in range(mini(colors.size(), unique_slots.size())):
		_apply_color_to_all_materials_for(unique_slots[i], colors[i])


## Unique SkinSlot refs in order of first appearance in `slots`.
func _unique_slots() -> Array[SkinSlot]:
	var out: Array[SkinSlot] = []
	for slot in slots:
		if slot != null and not out.has(slot):
			out.append(slot)
	return out


## Apply `color` to every runtime material whose position references `slot`.
func _apply_color_to_all_materials_for(slot: SkinSlot, color: Color) -> void:
	for i in range(slots.size()):
		if slots[i] != slot:
			continue
		var mat := _runtime_materials[i]
		if mat == null:
			continue
		slot.apply_color_to(mat, color)


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
