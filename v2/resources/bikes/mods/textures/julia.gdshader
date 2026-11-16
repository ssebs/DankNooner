// Mirror-tiled Julia set drawn as escape-count contours; c orbits so they morph (TextureMod overlay).
shader_type spatial;
render_mode blend_mix, unshaded, shadows_disabled;

uniform vec4 color_a : source_color = vec4(1.0, 0.25, 0.1, 1.0);
uniform vec4 color_b : source_color = vec4(1.0, 0.85, 0.2, 1.0);
uniform float scale : hint_range(0.5, 20.0) = 2.0;
uniform float speed : hint_range(0.0, 2.0) = 0.2;
uniform float line_width : hint_range(0.05, 1.0) = 0.3;
uniform float energy : hint_range(0.0, 8.0) = 1.2;

const int MAX_ITER = 48;

void fragment() {
	vec2 z = (abs(fract(UV * scale) - 0.5) * 2.0 - 0.5) * 1.4;
	float t = TIME * speed;
	vec2 c = 0.7885 * vec2(cos(t), sin(t));
	float escaped = 0.0;
	float n = 0.0;
	for (int i = 0; i < MAX_ITER; i++) {
		z = vec2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
		if (dot(z, z) > 16.0) {
			escaped = 1.0;
			// Smooth iteration count, so bands don't step.
			n = float(i) - log2(log2(dot(z, z))) + 4.0;
			break;
		}
	}
	// Contour lines of the escape count: steady coverage however sparse the set is at this c.
	float line = smoothstep(1.0 - line_width, 1.0, fract(n));

	ALBEDO = mix(color_a.rgb, color_b.rgb, n / float(MAX_ITER)) * energy;
	ALPHA = escaped * line;
}
