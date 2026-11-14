@tool
## Lays a material over the bike's paintable meshes (SkinColor.meshes), on top of its colors.
class_name TextureMod extends BikeMod

@export var material: Material


##override
func apply(vehicle_skin: Node3D) -> void:
	for mesh in vehicle_skin.mesh_skin.meshes:
		mesh.material_overlay = material
