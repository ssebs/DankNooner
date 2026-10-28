shader_type canvas_item;

// One soft dark pool per screen corner, under the HUD's corner groups.
uniform vec4 color : source_color = vec4(0.02, 0.027, 0.06, 0.55);
// Pool radius, as a fraction of the screen height.
uniform float radius = 0.5;

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 p = vec2(UV.x * aspect, UV.y);
	float d = min(
		min(distance(p, vec2(0.0)), distance(p, vec2(aspect, 0.0))),
		min(distance(p, vec2(0.0, 1.0)), distance(p, vec2(aspect, 1.0)))
	);
	COLOR = vec4(color.rgb, color.a * (1.0 - smoothstep(0.0, radius, d)));
}
