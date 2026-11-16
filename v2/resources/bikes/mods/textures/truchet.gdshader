// Random quarter-arc Truchet tiles with dashes flowing along the arcs (TextureMod overlay).
shader_type spatial;
render_mode blend_mix, unshaded, shadows_disabled;

uniform vec4 color_a : source_color = vec4(0.2, 1.0, 0.55, 1.0);
uniform vec4 color_b : source_color = vec4(1.0, 0.3, 0.9, 1.0);
uniform float scale : hint_range(1.0, 60.0) = 10.0;
uniform float speed : hint_range(0.0, 5.0) = 1.0;
uniform float width : hint_range(0.02, 0.4) = 0.12;
uniform float dash_count : hint_range(1.0, 8.0) = 2.0;
uniform float energy : hint_range(0.0, 8.0) = 3.0;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 p = UV * scale;
	vec2 id = floor(p);
	vec2 f = fract(p) - 0.5;
	if (hash21(id) > 0.5) {
		f.x = -f.x;
	}
	vec2 q = length(f - 0.5) < length(f + 0.5) ? f - 0.5 : f + 0.5;
	float mask = smoothstep(width * 0.5, width * 0.5 - 0.03, abs(length(q) - 0.5));
	// Checker parity flips the flow so it reads continuous across neighbours.
	float dir = mod(id.x + id.y, 2.0) * 2.0 - 1.0;
	float dash = step(0.5, fract(atan(q.y, q.x) / (PI * 0.5) * dash_count + TIME * speed * dir));

	ALBEDO = mix(color_a.rgb, color_b.rgb, dash) * energy;
	ALPHA = mask * (0.45 + 0.55 * dash);
}
