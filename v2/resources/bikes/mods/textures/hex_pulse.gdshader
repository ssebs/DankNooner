// Glowing hex grid with rings pulsing outward and random cell flashes (TextureMod overlay).
shader_type spatial;
render_mode blend_mix, unshaded, shadows_disabled;

uniform vec4 line_color : source_color = vec4(0.255, 0.686, 1.0, 1.0);
uniform vec4 pulse_color : source_color = vec4(1.0, 0.3, 0.9, 1.0);
uniform float scale : hint_range(1.0, 60.0) = 12.0;
uniform float speed : hint_range(0.0, 5.0) = 0.6;
uniform float line_width : hint_range(0.01, 0.3) = 0.06;
uniform float energy : hint_range(0.0, 8.0) = 3.0;

const vec2 HEX = vec2(1.0, 1.7320508);

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 p = UV * scale;
	vec2 a = mod(p, HEX) - HEX * 0.5;
	vec2 b = mod(p - HEX * 0.5, HEX) - HEX * 0.5;
	vec2 local = dot(a, a) < dot(b, b) ? a : b;
	vec2 id = p - local;

	vec2 q = abs(local);
	float edge = 0.5 - max(dot(q, normalize(HEX)), q.x);
	float line = smoothstep(line_width, line_width * 0.4, edge);

	float pulse = pow(1.0 - fract(length(id) * 0.15 - TIME * speed), 8.0);
	float flash = step(0.92, hash21(id + floor(TIME * speed * 2.0))) * 0.35;

	ALBEDO = mix(line_color.rgb, pulse_color.rgb, max(pulse, flash * 2.0)) * energy;
	ALPHA = max(line * (0.35 + 0.65 * pulse), flash);
}
