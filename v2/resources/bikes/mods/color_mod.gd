@tool
class_name ColorMod extends BikeMod

## Slot colors (use TRANSPARENT to skip a slot, same convention as BikeSkinDefinition.colors)
@export var colors: Array[Color] = []


##override
func apply(bike_skin: BikeSkin) -> void:
	for i in colors.size():
		if colors[i] != Color.TRANSPARENT:
			bike_skin.mesh_skin.update_slot_color(i, colors[i])
