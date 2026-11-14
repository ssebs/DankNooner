shader_type canvas_item;

// Neon outline around a texture's opaque shape (InputPrompt's gamepad glyphs), outer edge only.
// The glyph is inset by `width` so the outline isn't clipped at the rect's edge.
uniform vec4 outline_color : source_color = vec4(0.255, 0.686, 1.0, 0.75);
uniform float width = 0.08; // fraction of the rect

varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

float alpha_at(sampler2D tex, vec2 uv) {
	// Sampling clamps at the edge, which would smear the border pixels outward
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return 0.0;
	}
	// Explicit LOD: implicit derivatives are undefined inside these loops
	return textureLod(tex, uv, 0.0).a;
}

// A hole inside the glyph (e.g. a button's letter) has the glyph in every direction; the outside
// reaches the rect's edge along at least one ray.
bool is_enclosed(sampler2D tex, vec2 uv) {
	int hits = 0;
	for (int i = 0; i < 8; i++) {
		vec2 dir = vec2(cos(TAU * float(i) / 8.0), sin(TAU * float(i) / 8.0));
		float hit = 0.0;
		for (int s = 1; s <= 32; s++) {
			hit = max(hit, step(0.5, alpha_at(tex, uv + dir * float(s) / 24.0)));
		}
		hits += int(hit);
	}
	return hits == 8;
}

void fragment() {
	vec2 uv = UV * (1.0 + 2.0 * width) - width;
	vec4 glyph = vec4(textureLod(TEXTURE, uv, 0.0).rgb, alpha_at(TEXTURE, uv)) * modulate;
	float ring = 0.0;
	if (glyph.a < 0.99 && !is_enclosed(TEXTURE, uv)) {
		for (int i = 0; i < 16; i++) {
			vec2 dir = vec2(cos(TAU * float(i) / 16.0), sin(TAU * float(i) / 16.0));
			ring = max(ring, max(alpha_at(TEXTURE, uv + dir * width), alpha_at(TEXTURE, uv + dir * width * 0.5)));
		}
	}
	float edge_a = outline_color.a * ring * (1.0 - glyph.a);
	COLOR = vec4(mix(outline_color.rgb, glyph.rgb, glyph.a / max(glyph.a + edge_a, 0.0001)), glyph.a + edge_a);
}
