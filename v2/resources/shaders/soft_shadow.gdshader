shader_type canvas_item;

// Soft drop shadow of a texture's alpha. Draw on a copy of the texture behind the original, its
// rect grown by `pad` (a fraction of the original rect, via anchors) so the blur isn't clipped.
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.85);
uniform vec2 pad = vec2(0.03, 0.13);
uniform vec2 offset_px = vec2(3.0, 5.0);
uniform float blur_px = 8.0;

float alpha_at(sampler2D tex, vec2 uv) {
	// Sampling clamps at the edge, which would smear the border pixels outward
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return 0.0;
	}
	return texture(tex, uv).a;
}

void fragment() {
	vec2 uv = UV * (1.0 + 2.0 * pad) - pad - offset_px * TEXTURE_PIXEL_SIZE;
	float a = 0.0;
	for (int x = -3; x <= 3; x++) {
		for (int y = -3; y <= 3; y++) {
			a += alpha_at(TEXTURE, uv +vec2(float(x), float(y)) / 3.0 * blur_px * TEXTURE_PIXEL_SIZE);
		}
	}
	COLOR = vec4(shadow_color.rgb, shadow_color.a * a / 49.0);
}
