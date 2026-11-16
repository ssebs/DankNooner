// Slow-breathing electric arcs crawling over the paint (TextureMod overlay).
shader_type spatial;
render_mode blend_mix, unshaded, shadows_disabled;

uniform vec4 bolt_color : source_color = vec4(0.55, 0.75, 1.0, 1.0);
uniform float scale : hint_range(0.5, 20.0) = 4.0;
uniform float speed : hint_range(0.0, 5.0) = 0.15;
uniform float line_px : hint_range(0.5, 8.0) = 1.5;
uniform float energy : hint_range(0.0, 8.0) = 3.0;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 u = smoothstep(0.0, 1.0, fract(p));
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = UV * scale;
	float t = TIME * speed;
	float n = fbm(p + vec2(t, 0.0) + fbm(p * 2.0 - t)) - 0.5;
	// Pixel distance to the n = 0 contour: stays a thin line where the noise is flat, not a blob.
	float d = abs(n) / max(fwidth(n), 1e-5);
	float bolt = smoothstep(line_px, 0.0, d);
	float glow = smoothstep(line_px * 4.0, 0.0, d) * 0.3;
	// Smooth, slow pulse: hard flicker read as a strobe.
	float pulse = 0.8 + 0.2 * sin(TIME * 1.5);

	ALBEDO = mix(bolt_color.rgb, vec3(1.0), bolt) * energy;
	ALPHA = max(bolt, glow) * pulse;
}
