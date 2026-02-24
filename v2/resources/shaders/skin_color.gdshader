shader_type spatial;

uniform vec3 replacement_color : source_color = vec3(1.0, 0.0, 0.0);
uniform sampler2D albedo_texture : source_color;
uniform sampler2D normal_texture : hint_normal;
uniform sampler2D glossiness_texture;
uniform sampler2D specular_texture;
uniform float tolerance : hint_range(0.0, 1.0) = 0.3;

void fragment() {
    vec4 tex = texture(albedo_texture, UV);

    // Detect magenta pixels (high R, low G, high B)
    float is_magenta = step(tex.g + tolerance, tex.r) * step(tex.g + tolerance, tex.b);
    ALBEDO = mix(tex.rgb, replacement_color * tex.r, is_magenta);

    NORMAL_MAP = texture(normal_texture, UV).rgb;
    ROUGHNESS = 1.0 - texture(glossiness_texture, UV).r; // glossiness is inverse of roughness
    SPECULAR = texture(specular_texture, UV).r;
}
