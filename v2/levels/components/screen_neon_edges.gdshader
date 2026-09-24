// Screen-space edge detection as a mesh overlay: only runs on the mesh's own pixels,
// so the glow is masked to that object. Values > 1 bloom with Environment glow.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, fog_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D normal_texture : hint_normal_roughness_texture, filter_nearest;

uniform vec3 edge_color : source_color = vec3(0.255, 0.686, 1.0);
uniform float edge_energy : hint_range(0.0, 16.0) = 4.0;
uniform float edge_width_px : hint_range(0.5, 8.0) = 1.5;
// Relative depth jump that counts as a silhouette
uniform float depth_threshold : hint_range(0.0, 1.0) = 0.05;
// 1 - dot(normals) that counts as a crease
uniform float normal_threshold : hint_range(0.0, 2.0) = 0.4;

void vertex() {
	// Nudge off the surface to avoid z-fighting with the base material
	VERTEX += NORMAL * 0.002;
}

float linear_depth(vec2 uv, mat4 inv_projection) {
	vec4 view = inv_projection * vec4(uv * 2.0 - 1.0, texture(depth_texture, uv).r, 1.0);
	return -view.z / view.w;
}

vec3 view_normal(vec2 uv) {
	return texture(normal_texture, uv).xyz * 2.0 - 1.0;
}

void fragment() {
	vec2 texel = edge_width_px / VIEWPORT_SIZE;
	vec2 offsets[4] = { vec2(texel.x, 0.0), vec2(-texel.x, 0.0), vec2(0.0, texel.y), vec2(0.0, -texel.y) };

	float depth = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	vec3 normal = view_normal(SCREEN_UV);
	float edge = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 uv = SCREEN_UV + offsets[i];
		float depth_jump = (linear_depth(uv, INV_PROJECTION_MATRIX) - depth) / depth;
		// A nearer neighbor is an occluder's outline, not ours
		if (depth_jump < -depth_threshold) {
			continue;
		}
		if (depth_jump > depth_threshold || 1.0 - dot(normal, view_normal(uv)) > normal_threshold) {
			edge = 1.0;
		}
	}
	ALBEDO = edge_color * edge_energy * edge;
}
