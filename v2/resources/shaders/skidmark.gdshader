// Black ink opaque, white background transparent (luminance → alpha) so it works
// whether or not the PNG carries an alpha channel. `fade` drives the fade-out.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_mix;

uniform sampler2D tex : source_color;
uniform float fade = 1.0;

void fragment() {
	vec4 t = texture(tex, UV);
	float ink = 1.0 - dot(t.rgb, vec3(0.299, 0.587, 0.114));
	ALBEDO = vec3(0.04);
	ALPHA = ink * t.a * fade;
}
