/* ============================================================
 * Name: Aurora Sky
 * Category: A - 3D Stylized Environments
 * Type: spatial
 * Placement: Apply to MeshInstance3D (plane/terrain/props as noted in name).
 * Description: Aurora Sky stylized environment effect with exposed uniforms.
 * ============================================================ */
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded, shadows_disabled;

uniform vec4 sky_color : source_color = vec4(0.02, 0.04, 0.12, 1.0);
uniform vec4 aurora_a : source_color = vec4(0.2, 1.0, 0.55, 1.0);
uniform vec4 aurora_b : source_color = vec4(0.4, 0.3, 1.0, 1.0);
uniform float speed : hint_range(0.0, 5.0) = 0.4;
uniform float band_scale : hint_range(0.5, 20.0) = 3.0;
uniform float intensity : hint_range(0.0, 5.0) = 1.5;
uniform float vertical_falloff : hint_range(0.1, 8.0) = 2.0;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}
float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
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
float voronoi(vec2 p) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash22(n + g);
			vec2 r = g + o - f;
			md = min(md, dot(r, r));
		}
	}
	return sqrt(md);
}

void fragment() {
	float y = UV.y;
	float wave = sin(UV.x * band_scale + TIME * speed + fbm(UV * 2.0) * 3.0);
	wave = abs(wave);
	float curtain = pow(wave, 2.0) * pow(1.0 - y, vertical_falloff);
	vec3 aur = mix(aurora_a.rgb, aurora_b.rgb, fbm(UV * 3.0 + TIME * speed * 0.2));
	vec3 col = mix(sky_color.rgb, aur, curtain * intensity);
	ALBEDO = col;
	EMISSION = aur * curtain * intensity;
	ALPHA = 1.0;
}
