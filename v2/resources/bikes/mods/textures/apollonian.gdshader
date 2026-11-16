// Mirror-tiled Apollonian gasket (repeated fold + circle inversion) that breathes and turns (TextureMod overlay).
shader_type spatial;
render_mode blend_mix, unshaded, shadows_disabled;

uniform vec4 color_a : source_color = vec4(1.0, 0.2, 0.8, 1.0);
uniform vec4 color_b : source_color = vec4(0.2, 0.9, 1.0, 1.0);
uniform float scale : hint_range(0.5, 20.0) = 2.0;
uniform float speed : hint_range(0.0, 2.0) = 0.3;
uniform float line_width : hint_range(0.001, 0.05) = 0.012;
uniform float energy : hint_range(0.0, 8.0) = 1.2;

const int MAX_ITER = 8;

void fragment() {
	vec2 p = abs(fract(UV * scale) - 0.5) * 2.0;
	float t = TIME * speed;
	p = mat2(vec2(cos(t * 0.5), sin(t * 0.5)), vec2(-sin(t * 0.5), cos(t * 0.5))) * p;
	// The inversion radius breathing is what makes the circles swell and nest.
	float k = 1.2 + 0.15 * sin(t);
	float s = 1.0;
	float orbit = 1e9;
	for (int i = 0; i < MAX_ITER; i++) {
		p = -1.0 + 2.0 * fract(0.5 * p + 0.5);
		float r2 = max(dot(p, p), 1e-4);
		orbit = min(orbit, r2);
		float f = k / r2;
		p *= f;
		s *= f;
	}
	// Distance to the gasket's circle edges, in the tile's own units.
	float d = 0.25 * abs(p.y) / s;
	float line = 1.0 - smoothstep(0.0, line_width, d);

	ALBEDO = mix(color_a.rgb, color_b.rgb, clamp(sqrt(orbit), 0.0, 1.0)) * energy;
	ALPHA = line;
}
