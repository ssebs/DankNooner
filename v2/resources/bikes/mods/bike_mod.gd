@tool
class_name BikeMod extends Resource

## Apply this mod's effect to a vehicle skin — any Node3D exposing `mesh_skin` (BikeSkin or
## CarSkin). Override in subclasses.
func apply(_vehicle_skin: Node3D) -> void:
	pass
