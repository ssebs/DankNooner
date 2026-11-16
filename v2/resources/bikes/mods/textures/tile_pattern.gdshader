// Scrolling repeating tile patterns, one per TextureMod (TextureMod overlay).
shader_type spatial;
render_mode blend_mix, unshaded, shadows_disabled;

uniform int pattern : hint_enum("Chevron", "Waves", "Polka", "Scales", "Checker", "Diamonds", "Spiral") = 0;
uniform vec4 color : source_color = vec4(1.0, 0.3, 0.9, 1.0);
uniform float scale : hint_range(1.0, 60.0) = 10.0;
uniform vec2 scroll = vec2(0.0, 1.0);
uniform float speed : hint_range(0.0, 5.0) = 0.5;
uniform float energy : hint_range(0.0, 8.0) = 2.0;

// Antialiased step: 0 below edge, 1 above, blended over w.
float fill(float edge, float x, float w) {
	return smoothstep(edge - w, edge + w, x);
}

void fragment() {
	vec2 p = UV * scale + scroll * TIME * speed;
	// fwidth of the continuous p, not of fract(p), so tile seams don't smear.
	float aa = length(fwidth(p));
	float row = mod(floor(p.y), 2.0);
	vec2 offset_tile = fract(p + vec2(row * 0.5, 0.0));
	float mask = 0.0;
	if (pattern == 0) {
		float v = sin(TAU * (p.y + abs(fract(p.x) - 0.5)));
		mask = fill(0.0, v, fwidth(v));
	} else if (pattern == 1) {
		float v = sin(TAU * (p.y + 0.15 * sin(p.x * TAU)));
		mask = fill(0.0, v, fwidth(v));
	} else if (pattern == 2) {
		float radius = 0.25 + 0.08 * sin(TIME * 2.0);
		mask = 1.0 - fill(radius, length(offset_tile - 0.5), aa);
	} else if (pattern == 3) {
		float d = length(offset_tile - vec2(0.5, 0.0));
		mask = fill(0.42, d, aa) * (1.0 - fill(0.5, d, aa));
	} else if (pattern == 4) {
		float v = sin(TAU * p.x) * sin(TAU * p.y);
		mask = fill(0.0, v, fwidth(v));
	} else if (pattern == 5) {
		vec2 f = abs(fract(p) - 0.5);
		mask = 1.0 - fill(0.35, f.x + f.y, aa);
	} else {
		// Two-armed log spiral per tile, turning in place (scroll still slides the tiles).
		vec2 f = fract(p) - 0.5;
		float v = sin(atan(f.y, f.x) * 2.0 + log(length(f)) * 6.0 - TIME * speed * TAU);
		mask = fill(0.0, v, fwidth(v));
	}

	ALBEDO = color.rgb * energy;
	ALPHA = mask;
}
