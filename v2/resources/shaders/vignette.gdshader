shader_type canvas_item;

// Darkens toward the screen edges so UI reads over a busy 3D backdrop. Draw on a full-rect
// ColorRect behind the UI.
uniform vec4 color : source_color = vec4(0.0, 0.0, 0.0, 0.85);
// Clear spot's center (UV); off-center pulls the dark toward the opposite edge.
uniform vec2 center = vec2(0.55, 0.5);
// In screen heights, from center: clear inside inner_radius, full `color` past outer_radius.
uniform float inner_radius : hint_range(0.0, 2.0) = 0.35;
uniform float outer_radius : hint_range(0.0, 2.0) = 1.1;

void fragment() {
	vec2 d = UV - center;
	// Aspect-correct so the falloff is round, not stretched to the screen
	d.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	COLOR = vec4(color.rgb, color.a * smoothstep(inner_radius, outer_radius, length(d)));
}
