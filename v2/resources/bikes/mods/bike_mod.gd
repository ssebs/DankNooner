@tool
class_name BikeMod extends Resource

## Garage cost once unlocked. ColorMod sets 0: colors are free.
@export var price: int = 200


## Apply this mod's effect to a vehicle skin — any Node3D exposing `mesh_skin` (BikeSkin or
## CarSkin). Override in subclasses.
func apply(_vehicle_skin: Node3D) -> void:
	pass
