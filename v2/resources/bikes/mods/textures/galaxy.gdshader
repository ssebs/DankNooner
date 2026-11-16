// Drifting nebula clouds with twinkling stars (TextureMod overlay).
shader_type spatial;
render_mode blend_mix, unshaded, shadows_disabled;

uniform vec4 nebula_a : source_color = vec4(0.45, 0.1, 0.85, 1.0);
uniform vec4 nebula_b : source_color = vec4(0.1, 0.6, 1.0, 1.0);
uniform vec4 star_color : source_color = vec4(1.0);
uniform float scale : hint_range(0.5, 20.0) = 4.0;
uniform float speed : hint_range(0.0, 2.0) = 0.15;
uniform float star_density : hint_range(4.0, 120.0) = 40.0;
uniform float energy : hint_range(0.0, 8.0) = 2.0;

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
	float n = fbm(p + vec2(fbm(p + t), fbm(p - t + 3.7)));
	float cloud = smoothstep(0.4, 0.8, n);

	vec2 cell = floor(UV * star_density);
	vec2 offset = vec2(hash21(cell + 1.3), hash21(cell + 7.1)) - 0.5;
	float h = hash21(cell);
	float twinkle = 0.5 + 0.5 * sin(TIME * 3.0 + h * 40.0);
	float star = smoothstep(0.1, 0.0, length(fract(UV * star_density) - 0.5 - offset * 0.7)) * step(0.85, h) * twinkle;

	ALBEDO = mix(mix(nebula_a.rgb, nebula_b.rgb, n), star_color.rgb, star) * energy;
	ALPHA = max(cloud * 0.85, star);
}
