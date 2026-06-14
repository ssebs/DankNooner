// Radial (zoom) blur driven from CameraController for the high-speed rush effect.
// Center of the screen stays sharp; blur streaks outward toward the edges.
// `strength` is set each frame from the player's speed factor (0 = off).
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
// Radius (in UV) around the center that stays unblurred. Wide so the blur sits in the
// outer ring / corners like a vignette, leaving the center of the view sharp.
uniform float clear_radius : hint_range(0.0, 1.0) = 0.65;
// Max sample offset back toward center at full strength + edge.
uniform float max_offset : hint_range(0.0, 0.5) = 0.12;

const int SAMPLES = 10;

void fragment() {
	vec2 dir = SCREEN_UV - vec2(0.5);
	float dist = length(dir);
	float mask = smoothstep(clear_radius, 0.9, dist) * strength;

	vec4 col = vec4(0.0);
	for (int i = 0; i < SAMPLES; i++) {
		float t = float(i) / float(SAMPLES - 1);
		vec2 uv = SCREEN_UV - dir * (t * max_offset * mask);
		col += texture(screen_tex, uv);
	}
	COLOR = col / float(SAMPLES);
}
