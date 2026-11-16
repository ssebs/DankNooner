// Endlessly zooming Sierpinski triangle; holes alternate between two colors by depth (TextureMod overlay).
shader_type spatial;
render_mode blend_mix, unshaded, shadows_disabled;

uniform vec4 color_a : source_color = vec4(0.255, 0.686, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(0.255, 1.0, 0.738, 1.0);
uniform float scale : hint_range(0.5, 20.0) = 2.0;
uniform float speed : hint_range(0.0, 2.0) = 0.15;
uniform float energy : hint_range(0.0, 8.0) = 1.5;

const float CELLS = 64.0;

void fragment() {
	// Self-similar at 2x, so zooming 1x -> 2x and wrapping loops seamlessly.
	float zoom = exp2(fract(TIME * speed));
	vec2 uv = abs(fract(UV * scale) - 0.5) * 2.0;
	ivec2 cell = ivec2(uv / zoom * CELLS);
	// Pascal's triangle mod 2: x & y == 0 is in the set, the rest are the removed holes.
	int hole = cell.x & cell.y;
	// +fract keeps the color continuous across the zoom wrap (depth steps up by one).
	float depth = log2(float(max(hole, 1))) + fract(TIME * speed);

	ALBEDO = mix(color_a.rgb, color_b.rgb, 0.5 + 0.5 * cos(PI * depth)) * energy;
	ALPHA = hole > 0 ? 1.0 : 0.0;
}
