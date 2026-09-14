shader_type spatial;
render_mode unshaded;

group_uniforms FlameShape;
uniform bool apply_shape_deform = false; // use only for a cylindric shape flame
uniform float top_radius : hint_range(0.0, 1.5);
uniform float bottom_radius : hint_range(0.0, 1.5);
uniform float center_radius : hint_range(0.0, 5.0);
uniform float center_position : hint_range(0.0, 1.0);
uniform float cylinder_height : hint_range(0.0, 10.0) = 1.0;
uniform float bottom_curve = 0.4;
uniform float _vibrate_amplitude = 0.015;
uniform float _vibrate_frequency = 200.0;
group_uniforms;

group_uniforms FlameAppearance;
uniform float _speed = 2.0;
uniform float _scale = 2.0;
uniform vec4 color_inner : source_color = vec4(1.353, 0.919, 0.416, 0.0);
uniform vec4 color_outer : source_color = vec4(0.737, 0.141, 0.0, 0.678);
uniform float color_threshold : hint_range(0.0, 1.0) = 0.5;
uniform float flame_height = 1.0;
uniform float flame_height_offset = 0.0;
uniform float pattern_scale = 2.5;
uniform bool use_additional_texture = false;
uniform sampler2D flame_additional_texture : source_color;
uniform float texture_scale = 1.0;
uniform float texture_blend : hint_range(0.0, 1.0) = 1.0;
group_uniforms;

group_uniforms ToonOutline;
uniform bool outline_enabled = true;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float outline_thickness : hint_range(0.0, 0.15) = 0.04;
group_uniforms;

varying vec3 local_pos;

void vertex() {
	vec3 v_pos = VERTEX;

	if (apply_shape_deform) {
		float original_height = v_pos.y;
		float relative_height = (original_height + 1.0) / 2.0;

		float scaledHeight = relative_height * cylinder_height;
		v_pos.y = scaledHeight + sin(TIME * _vibrate_frequency) * _vibrate_amplitude;

		float radius;
		if (relative_height <= center_position) {
			float t = relative_height / center_position;
			t = pow(t, bottom_curve);
			t = smoothstep(0.0, 1.0, t);
			radius = mix(bottom_radius, center_radius, t);
		} else {
			float t = (relative_height - center_position) / (1.0 - center_position);
			t = smoothstep(0.0, 1.0, t);
			radius = mix(center_radius, top_radius, t);
		}

		float current_radius = length(vec2(v_pos.x, v_pos.z));
		if (current_radius > 0.0) {
			float scale_factor = radius / current_radius;
			v_pos.x *= scale_factor;
			v_pos.z *= scale_factor;
		}
	}

	local_pos = v_pos;
	VERTEX = v_pos;
}

vec3 mod2893(vec3 x) {
	return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 mod289(vec4 x) {
	return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 permute(vec4 x) {
	return mod289(((x * 34.0) + 1.0) * x);
}

vec4 taylorInvSqrt(vec4 r) {
	return 1.79284291400159 - 0.85373472095314 * r;
}

float snoise(vec3 v) {
	const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
	const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);

	vec3 i  = floor(v + dot(v, C.yyy));
	vec3 x0 = v - i + dot(i, C.xxx);

	vec3 g = step(x0.yzx, x0.xyz);
	vec3 l = 1.0 - g;
	vec3 i1 = min(g.xyz, l.zxy);
	vec3 i2 = max(g.xyz, l.zxy);

	vec3 x1 = x0 - i1 + C.xxx;
	vec3 x2 = x0 - i2 + C.yyy;
	vec3 x3 = x0 - D.yyy;

	i = mod2893(i);
	vec4 p = permute(permute(permute(
		i.z + vec4(0.0, i1.z, i2.z, 1.0))
		+ i.y + vec4(0.0, i1.y, i2.y, 1.0))
		+ i.x + vec4(0.0, i1.x, i2.x, 1.0));

	float n_ = 0.142857142857;
	vec3 ns = n_ * D.wyz - D.xzx;

	vec4 j = p - 49.0 * floor(p * ns.z * ns.z);

	vec4 x_ = floor(j * ns.z);
	vec4 y_ = floor(j - 7.0 * x_);

	vec4 x = x_ * ns.x + ns.yyyy;
	vec4 y = y_ * ns.x + ns.yyyy;
	vec4 h = 1.0 - abs(x) - abs(y);

	vec4 b0 = vec4(x.xy, y.xy);
	vec4 b1 = vec4(x.zw, y.zw);

	vec4 s0 = floor(b0) * 2.0 + 1.0;
	vec4 s1 = floor(b1) * 2.0 + 1.0;
	vec4 sh = -step(h, vec4(0.0));

	vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
	vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;

	vec3 p0 = vec3(a0.xy, h.x);
	vec3 p1 = vec3(a0.zw, h.y);
	vec3 p2 = vec3(a1.xy, h.z);
	vec3 p3 = vec3(a1.zw, h.w);

	vec4 norm = taylorInvSqrt(vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
	p0 *= norm.x;
	p1 *= norm.y;
	p2 *= norm.z;
	p3 *= norm.w;

	vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
	m = m * m;
	return 42.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

float getNoise(vec3 pos, float t) {
	float SCALE = _scale;
	float noise = snoise(vec3(pos.x * SCALE, pos.y * SCALE * 4.0 + t * _speed, pos.z * SCALE));

	SCALE = 6.0;
	noise += snoise(vec3(pos.x * SCALE + t * _speed, pos.y * SCALE, pos.z * SCALE)) * 0.2;

	noise = (noise / 2.0 + 0.5);
	return noise;
}

float getDepth(float n, float cutoff, float steps) {
	float d = (n - cutoff) / (1.0 - cutoff);
	d = floor(d * steps) / steps;
	return d;
}

float getNoiseAt(vec3 pos, float height01, float t) {
	float cutoff = 1.1 - height01 * 2.5;
	float noise = getNoise(pos, t);
	return step(cutoff, noise);
}

void fragment() {
	float steps = 4.0;

	float height01 = clamp((local_pos.y - flame_height_offset) / max(flame_height, 0.0001), 0.0, 1.0);

	vec3 pos = local_pos;
	pos.x *= pattern_scale;
	pos.z *= pattern_scale;

	float t = TIME * 3.0;

	float cutoff = 1.1 - height01 * 2.5;
	float noise = getNoise(pos, t);

	if (noise < cutoff) {
		if (outline_enabled) {
			float d = outline_thickness;
			float n_up    = getNoiseAt(pos + vec3(0.0,  d, 0.0), height01, t);
			float n_down  = getNoiseAt(pos + vec3(0.0, -d, 0.0), height01, t);
			float n_left  = getNoiseAt(pos + vec3(-d,  0.0, 0.0), height01, t);
			float n_right = getNoiseAt(pos + vec3( d,  0.0, 0.0), height01, t);

			float edge = max(max(n_up, n_down), max(n_left, n_right));

			if (edge > 0.5) {
				ALBEDO = outline_color.rgb;
				ALPHA = outline_color.a;
			} else {
				ALPHA = 0.0;
			}
		} else {
			ALPHA = 0.0;
		}
} else {
		float d = getDepth(noise, cutoff, steps);
		vec3 col = d >= color_threshold ? color_inner.rgb : color_outer.rgb;

		if (use_additional_texture) {
			vec3 blend_weights = abs(NORMAL);
			blend_weights /= (blend_weights.x + blend_weights.y + blend_weights.z);

			vec3 tex_pos = local_pos * texture_scale;
			vec3 tex_x = texture(flame_additional_texture, tex_pos.yz).rgb;
			vec3 tex_y = texture(flame_additional_texture, tex_pos.xz).rgb;
			vec3 tex_z = texture(flame_additional_texture, tex_pos.xy).rgb;
			vec3 tex_color = tex_x * blend_weights.x + tex_y * blend_weights.y + tex_z * blend_weights.z;

			col = mix(col, col * tex_color, texture_blend);
		}

		ALBEDO = col * 1.5;
		ALPHA = 1.0;
	}
}