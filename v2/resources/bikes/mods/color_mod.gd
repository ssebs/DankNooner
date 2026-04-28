@tool
class_name ColorMod extends BikeMod

## Slot colors (use TRANSPARENT to skip a slot, same convention as BikeSkinDefinition.colors)
@export var colors: Array[Color] = []


##override
func apply(bike_skin: BikeSkin) -> void:
	bike_skin.mesh_skin.update_all_colors(colors)
