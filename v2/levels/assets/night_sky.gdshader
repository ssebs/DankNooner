shader_type sky;

group_uniforms sky;
uniform vec3 zenith_color : source_color = vec3(0.01, 0.015, 0.08);
uniform vec3 horizon_color : source_color = vec3(0.12, 0.05, 0.3);
uniform vec3 ground_color : source_color = vec3(0.02, 0.01, 0.05);
uniform vec3 city_glow_color : source_color = vec3(1.0, 0.25, 0.55);
uniform float city_glow_height : hint_range(0.01, 0.5) = 0.08;
uniform float city_glow_energy : hint_range(0.0, 4.0) = 0.8;
// 0 = smooth gradient
uniform int sky_bands : hint_range(0, 16) = 6;

group_uniforms stars;
uniform float star_scale : hint_range(20.0, 400.0) = 50.0;
uniform float star_density : hint_range(0.0, 1.0) = 0.2;
uniform float star_size : hint_range(0.01, 0.3) = 0.2;
uniform float star_energy : hint_range(0.0, 10.0) = 3.0;
uniform float twinkle_speed : hint_range(0.0, 10.0) = 3.0;

group_uniforms moon;
uniform vec3 moon_color : source_color = vec3(1.0, 0.93, 0.85);
uniform vec3 moon_crater_color : source_color = vec3(0.7, 0.62, 0.8);
uniform float moon_radius : hint_range(0.01, 0.3) = 0.06;
uniform float moon_energy : hint_range(0.0, 10.0) = 3.0;
uniform vec3 halo_color : source_color = vec3(0.45, 0.3, 1.0);
uniform float halo_radius : hint_range(0.05, 1.0) = 0.35;
uniform int halo_rings : hint_range(1, 8) = 3;

group_uniforms clouds;
uniform vec3 cloud_dark_color : source_color = vec3(0.05, 0.03, 0.15);
uniform vec3 cloud_lit_color : source_color = vec3(0.25, 0.15, 0.45);
uniform float cloud_scale : hint_range(0.1, 5.0) = 0.8;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.3;
uniform float cloud_rim_width : hint_range(0.0, 0.2) = 0.015;
uniform vec2 cloud_wind = vec2(0.01, 0.004);
group_uniforms;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

vec3 sky_gradient(vec3 dir) {
	float t = sqrt(max(dir.y, 0.0));
	if (sky_bands > 0) {
		t = round(t * float(sky_bands)) / float(sky_bands);
	}
	vec3 col = mix(horizon_color, zenith_color, t);
	col += city_glow_color * city_glow_energy * exp(-t * t / city_glow_height);
	return mix(col, ground_color, smoothstep(0.0, -0.05, dir.y));
}

// Cube-face grid avoids the pole pinching of a lat/long grid.
vec2 cube_face_uv(vec3 dir, out float face) {
	vec3 a = abs(dir);
	if (a.x >= a.y && a.x >= a.z) {
		face = sign(dir.x);
		return dir.yz / a.x;
	}
	if (a.y >= a.z) {
		face = 2.0 + sign(dir.y);
		return dir.xz / a.y;
	}
	face = 4.0 + sign(dir.z);
	return dir.xy / a.z;
}

float stars(vec3 dir) {
	float face;
	vec2 uv = cube_face_uv(dir, face) * star_scale;
	vec2 cell = floor(uv);
	vec2 seed = cell + face * 1000.0;
	if (hash21(seed) > star_density) {
		return 0.0;
	}
	// Jitter stays inside the cell so a star never gets clipped by its border
	vec2 star_pos = cell + 0.3 + 0.4 * hash22(seed);
	float twinkle = 0.6 + 0.4 * sin(TIME * twinkle_speed + hash21(seed + 7.0) * TAU);
	// Solid core so TAA doesn't smear stars away while the camera moves
	return (1.0 - smoothstep(star_size * 0.5, star_size, length(uv - star_pos))) * twinkle;
}

vec3 add_moon(vec3 col, vec3 dir, vec3 moon_dir) {
	float angle = acos(clamp(dot(dir, moon_dir), -1.0, 1.0));

	float halo = max(1.0 - angle / halo_radius, 0.0);
	halo = ceil(halo * float(halo_rings)) / float(halo_rings);
	col += halo_color * halo * halo * 0.5;

	vec3 right = normalize(cross(moon_dir, vec3(0.0, 1.0, 0.0)));
	vec3 up = cross(right, moon_dir);
	vec2 moon_uv = vec2(dot(dir, right), dot(dir, up)) / moon_radius;
	float crater = step(0.62, value_noise(moon_uv * 3.0));
	vec3 surface = mix(moon_color, moon_crater_color, crater) * moon_energy;
	return mix(col, surface, 1.0 - smoothstep(moon_radius * 0.97, moon_radius, angle));
}

// rgb = color, a = coverage
vec4 clouds(vec3 dir, vec3 moon_dir) {
	vec2 uv = dir.xz / (dir.y + 0.15) * cloud_scale + TIME * cloud_wind;
	float density = fbm(uv);
	float threshold = 1.0 - cloud_coverage;
	float mask = smoothstep(threshold, threshold + 0.01, density);
	float core = smoothstep(threshold + cloud_rim_width, threshold + cloud_rim_width + 0.01, density);

	// Toon lighting: lit where density falls off toward the moon
	float density_toward_moon = fbm(uv + moon_dir.xz * 0.1);
	vec3 body = mix(cloud_dark_color, cloud_lit_color, step(density_toward_moon, density));

	// Edges underlit by the city glow, strongest near the horizon
	float near_horizon = 1.0 - smoothstep(0.0, 0.5, dir.y);
	vec3 rim = city_glow_color * city_glow_energy * mix(0.2, 0.8, near_horizon);

	return vec4(mix(rim, body, core), mask * smoothstep(0.0, 0.1, dir.y));
}

void sky() {
	vec3 col = sky_gradient(EYEDIR);
	// Reflections don't need the detail, and TIME forces a per-frame radiance update
	if (AT_CUBEMAP_PASS) {
		COLOR = col;
	} else {
		vec3 moon_dir = LIGHT0_ENABLED ? LIGHT0_DIRECTION : vec3(0.0, 1.0, 0.0);
		col += stars(EYEDIR) * star_energy * smoothstep(0.0, 0.2, EYEDIR.y);
		if (LIGHT0_ENABLED) {
			col = add_moon(col, EYEDIR, moon_dir);
		}
		vec4 cloud = clouds(EYEDIR, moon_dir);
		COLOR = mix(col, cloud.rgb, cloud.a);
	}
}
