// Rainbow plasma bands flowing over the paint (TextureMod overlay).
shader_type spatial;
render_mode blend_mix, unshaded, shadows_disabled;

uniform float scale : hint_range(0.5, 40.0) = 8.0;
uniform float speed : hint_range(0.0, 5.0) = 1.0;
uniform float energy : hint_range(0.0, 8.0) = 2.0;
uniform float coverage : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec2 p = UV * scale;
	float t = TIME * speed;
	vec2 center = vec2(sin(t * 0.5), cos(t * 0.4)) * scale * 0.5;
	float v = sin(p.x + t) + sin(p.y * 0.8 - t * 1.3) + sin((p.x + p.y) * 0.7 + t * 0.7) + sin(length(p - center) - t);
	float band = 0.5 + 0.5 * sin(v * PI);
	ALBEDO = (0.5 + 0.5 * cos(TAU * (v * 0.25 + vec3(0.0, 0.33, 0.67)))) * energy;
	ALPHA = smoothstep(1.0 - coverage, 1.15 - coverage, band);
}
