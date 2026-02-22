shader_type spatial;

uniform vec3 replacement_color : source_color = vec3(1.0, 0.0, 0.0);

void fragment() {
    ALBEDO = replacement_color;
}
