// Mirror-tiled Kali-set fractal with an animated fold constant (TextureMod overlay).
shader_type spatial;
render_mode blend_mix, unshaded, shadows_disabled;

// Off: shades between color_a and color_b instead of a full hue cycle.
uniform bool rainbow = true;
uniform vec4 color_a : source_color = vec4(0.255, 0.686, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(0.1, 0.27, 0.4, 1.0);
uniform float scale : hint_range(0.5, 20.0) = 3.0;
uniform float speed : hint_range(0.0, 2.0) = 0.25;
uniform float sharpness : hint_range(10.0, 1000.0) = 250.0;
uniform float energy : hint_range(0.0, 8.0) = 1.2;

void fragment() {
	// abs(fract - 0.5) mirrors each tile, so the repeat has no seams.
	vec2 p = abs(fract(UV * scale) - 0.5) * 2.0;
	float t = TIME * speed;
	vec2 c = vec2(0.55, 0.45) + 0.12 * vec2(sin(t), cos(t * 0.7));
	float trap = 1e9;
	for (int i = 0; i < 8; i++) {
		p = abs(p) / max(dot(p, p), 1e-3) - c;
		trap = min(trap, abs(p.x * p.y));
	}
	float glow = exp(-trap * sharpness);

	float phase = trap * 2.0 + t * 0.3;
	vec3 col = mix(color_a.rgb, color_b.rgb, 0.5 + 0.5 * cos(TAU * phase));
	if (rainbow) {
		col = 0.5 + 0.5 * cos(TAU * (phase + vec3(0.0, 0.33, 0.67)));
	}
	ALBEDO = col * energy;
	ALPHA = clamp(glow, 0.0, 1.0);
}
