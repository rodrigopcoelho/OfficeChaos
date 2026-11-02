shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// Flat illustrated office floor: two-tone tiles with inked seams, a hand-printed
// stipple texture, and corruption (ink cracks + glowing glitch tiles) that grows
// with distance from the level's start point.

uniform vec4 base_color : source_color = vec4(0.55, 0.53, 0.47, 1.0);
uniform vec4 seam_color : source_color = vec4(0.4, 0.38, 0.33, 1.0);
uniform float tile_size = 2.0;
uniform float pattern = 0.0;
uniform vec4 corrupt_color : source_color = vec4(1.0, 0.3, 0.55, 1.0);
uniform vec4 ink : source_color = vec4(0.12, 0.09, 0.16, 1.0);
uniform vec3 corrupt_origin = vec3(0.0);
uniform float corrupt_start = 999.0;
uniform float corrupt_end = 1000.0;
uniform float corrupt_base = 0.0;

varying vec3 wp;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x),
			   mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wp.xz / tile_size;
	vec2 f = fract(uv);
	vec2 id = floor(uv);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float seam = 1.0 - step(0.012, edge);
	vec3 c = base_color.rgb;
	if (pattern > 0.5) {
		c = mix(c, seam_color.rgb, mod(id.x + id.y, 2.0) * 0.55);
	}
	// printed stipple: sparse dots of the seam colour
	vec2 dots = wp.xz * 9.0;
	float dot_mask = step(0.93, hash2(floor(dots))) * step(length(fract(dots) - 0.5), 0.3);
	c = mix(c, seam_color.rgb, dot_mask * 0.5);
	c = mix(c, seam_color.rgb * 0.8, seam);

	float cor = clamp(corrupt_base + smoothstep(corrupt_start, corrupt_end, distance(wp.xz, corrupt_origin.xz)), 0.0, 1.0);
	float cn = vnoise(wp.xz * 0.55 + vec2(7.0, 3.0));
	float crack = 1.0 - step(0.009, abs(cn - 0.5));
	float crack_glow = 1.0 - smoothstep(0.0, 0.06, abs(cn - 0.5));
	c = mix(c, ink.rgb, crack * step(0.25, cor));
	float glitch_tile = step(1.0 - cor * 0.05, hash2(id + vec2(floor(TIME * 3.0), 0.0)));
	c = mix(c, corrupt_color.rgb, glitch_tile * 0.8);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	float pulse = 0.6 + 0.4 * sin(TIME * 2.0 + wp.x * 0.35 + wp.z * 0.2);
	EMISSION = corrupt_color.rgb * (crack_glow * (1.0 - crack) * cor * pulse * 1.2 + glitch_tile * 0.5);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		float lit = smoothstep(0.3, 0.45, ATTENUATION);
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * lit * clamp(dot(NORMAL, LIGHT) * 4.0, 0.0, 1.0);
	} else {
		float a = ATTENUATION * clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * smoothstep(0.2, 0.23, a) * 0.18;
	}
}
