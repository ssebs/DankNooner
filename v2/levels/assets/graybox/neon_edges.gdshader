// Additive overlay that lights up the edges of a box/plane. Values > 1 bloom with Environment glow.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, fog_disabled;

// Plain uniforms, not instance uniforms: WebGL's instance buffer only fits a few hundred meshes
uniform vec3 edge_color : source_color = vec3(0.255, 0.686, 1.0);
uniform float edge_energy : hint_range(0.0, 16.0) = 4.0;
uniform float edge_width : hint_range(0.0, 1.0) = 0.06;
// Mesh size in local units; y = 0 for a plane
uniform vec3 size = vec3(1.0);

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
	// Nudge off the surface to avoid z-fighting with the base material
	VERTEX += NORMAL * 0.002;
}

void fragment() {
	vec3 d = size * 0.5 - abs(local_pos);
	// On a face one component is ~0, so the median is the distance to the nearest edge
	float edge_dist = d.x + d.y + d.z - min(d.x, min(d.y, d.z)) - max(d.x, max(d.y, d.z));
	// Floor the width at ~1px on screen so distant edges don't break into dots,
	// and dim by the true coverage so they fade with distance instead of thickening
	float px = length(vec2(dFdx(edge_dist), dFdy(edge_dist)));
	float width = max(edge_width, px);
	float coverage = edge_width / width;
	// Pad the falloff by a pixel either side so the outer boundary is antialiased at any distance
	ALBEDO = edge_color * edge_energy * coverage * (1.0 - smoothstep(width * 0.5 - px, width + px, edge_dist));
}
