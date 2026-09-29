shader_type canvas_item;

// Recolors a flat-color icon: keeps its alpha, replaces its color.
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	COLOR = vec4(tint.rgb, texture(TEXTURE, UV).a * tint.a);
}
