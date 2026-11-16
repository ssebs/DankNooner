// Mirror-tiled moiré: two drifting sets of rings whose interference bands crawl (TextureMod overlay).
shader_type spatial;
render_mode blend_mix, unshaded, shadows_disabled;

uniform vec4 color_a : source_color = vec4(0.6, 0.2, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(1.0, 0.55, 0.1, 1.0);
uniform float scale : hint_range(0.5, 20.0) = 1.5;
uniform float speed : hint_range(0.0, 2.0) = 0.4;
uniform float rings : hint_range(5.0, 120.0) = 45.0;
uniform float energy : hint_range(0.0, 8.0) = 1.2;

void fragment() {
	vec2 p = abs(fract(UV * scale) - 0.5) * 2.0;
	float t = TIME * speed;
	vec2 a = vec2(0.5) + 0.35 * vec2(sin(t), cos(t * 1.3));
	vec2 b = vec2(0.5) - 0.35 * vec2(sin(t * 0.8), cos(t));
	float wa = sin(length(p - a) * rings - t * 3.0);
	float wb = sin(length(p - b) * rings + t * 2.0);
	// The product's sign flips where the two ring sets fall out of phase: those are the bands.
	float band = wa * wb;

	ALBEDO = mix(color_a.rgb, color_b.rgb, 0.5 + 0.5 * wa) * energy;
	ALPHA = smoothstep(0.1, 0.4, band);
}
