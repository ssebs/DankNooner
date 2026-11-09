## Hold-to-pick loadout slots above the minimap, top = loadout 1. InputStateManager owns the input;
## RidingHUDState feeds it the highlighted slot.
class_name LoadoutBar extends VBoxContainer

const THUMB_SCENE := preload("res://utils/components/thumbnail_3d.tscn")
const THUMB_SIZE := Vector2(96, 64)
## Loadouts the running event won't let you swap to.
const LOCKED_ALPHA: float = 0.35
## Unpicked slot names, matching the theme's DimLabel.
const DIM_COLOR := Color(1, 1, 1, 0.6)


## can_swap: InputStateManager.can_swap_loadout, so locked slots read the same rule the swap uses.
func open(player_def: PlayerDefinition, can_swap: Callable) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for i in player_def.loadouts.size():
		var loadout := player_def.loadouts[i]
		var slot := HBoxContainer.new()
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.modulate.a = 1.0 if can_swap.call(i) else LOCKED_ALPHA
		var panel := PanelContainer.new()
		panel.theme_type_variation = &"ObjectPanel"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var thumb: Thumbnail3D = THUMB_SCENE.instantiate()
		thumb.custom_minimum_size = THUMB_SIZE
		panel.add_child(thumb)
		thumb.set_skin(Thumbnail3D.Type.BIKE, loadout.bike)
		slot.add_child(panel)
		var label := Label.new()
		label.modulate = DIM_COLOR
		# Same name + current marker as the garage tabs.
		var loadout_name := loadout.name if loadout.name != "" else str(i + 1)
		label.text = ("* " if i == player_def.active_loadout_index else "") + loadout_name
		slot.add_child(label)
		add_child(slot)
	show()


## Highlight one slot: its name lights up blue and its thumbnail pops.
func pick(index: int) -> void:
	# Color only: a font change would re-sort the row, and containers reset the pop's scale.
	for i in get_child_count():
		(get_child(i).get_child(1) as Label).modulate = UtilsConstants.UI_BLUE if i == index else DIM_COLOR
	# Deferred: a just-opened slot has no size (pop's pivot) until the bar sorts
	HUDFlash.pop.call_deferred(get_child(index).get_child(0))
