@tool
## Per-side material + collision settings for a track segment's runoff or wall.
## Instanced inline on a TrackPoint; leave a field's owning export null to fall
## back to the Track's road-wide defaults.
class_name SurfaceConfig extends Resource

## Tint preset, reusing the GrayBox color table via MaterialPresets.
@export var material_preset: MaterialPresets.Preset = MaterialPresets.Preset.DARK_GRAY

## Optional texture override. Null = use the Track's default texture.
@export var texture: Texture2D

## Physics collision layer bitmask for this feature's StaticBody3D.
@export_flags_3d_physics var collision_layer: int = 1
