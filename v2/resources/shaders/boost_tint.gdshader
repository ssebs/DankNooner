// Boost tint driven from CameraController while PlayerEntity.is_boosting: washes boost_color in
// from the screen edges, leaving the center clear. Alpha-blended, so no screen texture copy.
shader_type canvas_item;

uniform float boost : hint_range(0.0, 1.0) = 0.0;
uniform vec3 boost_color : source_color = vec3(0.25, 0.69, 1.0);
// How far the tint pushes the screen toward boost_color at full boost + edge.
uniform float boost_tint_amount : hint_range(0.0, 1.0) = 0.55;
// Radius (in UV) around the center the tint fades out by.
uniform float boost_clear_radius : hint_range(0.0, 1.0) = 0.15;

void fragment() {
	float mask = smoothstep(boost_clear_radius, 1.0, length(SCREEN_UV - vec2(0.5))) * boost;
	COLOR = vec4(boost_color, mask * boost_tint_amount);
}
