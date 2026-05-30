@tool
## Shared color-preset + triplanar material helper. Originally lived on
## GrayBoxStaticBody; extracted so the track builder reuses the same tint table
## and triplanar setup. Static-only — never instanced.
class_name MaterialPresets

# Member ORDER must stay identical to the old GrayBoxStaticBody.GrayBoxColor —
# existing scenes store color_preset as ints, so an order-preserving rename
# keeps those values valid.
enum Preset { DARK_GRAY, LIGHT_GRAY, GREEN, BLUE, RED, PURPLE, TAN }

const COLOR_VALUES: Dictionary = {
	Preset.DARK_GRAY: Color(1.0, 1.0, 1.0),
	Preset.LIGHT_GRAY: Color(2.363, 2.363, 2.363),
	Preset.GREEN: Color(0.729, 1.857, 0.365),
	Preset.BLUE: Color(0.365, 1.787, 1.857),
	Preset.RED: Color(1.975, 0.209, 0.209),
	Preset.PURPLE: Color(2.113, 1.029, 2.418),
	Preset.TAN: Color(2.807, 2.352, 1.369)
}


## Builds a triplanar StandardMaterial3D tinted by preset. Triplanar tiles the
## texture in world space, so it repeats correctly on any mesh size with no
## per-mesh UV math.
static func make_material(preset: Preset, texture: Texture2D) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.uv1_triplanar = true
	mat.albedo_color = COLOR_VALUES.get(preset, Color.WHITE)
	return mat
