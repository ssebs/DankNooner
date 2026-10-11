shader_type canvas_item;

// Crops to the largest centered circle with a soft 1px edge, e.g. square avatars in a round frame.
void fragment() {
	float dist = length(UV - vec2(0.5));
	COLOR.a *= 1.0 - smoothstep(0.5 - fwidth(dist), 0.5, dist);
}
