shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// Flat illustrated office floor: two-tone tiles with inked seams, a hand-printed
// stipple texture, and corruption (snaking data cables + glitch tiles) that grows
// with distance from the level's start point.
// The cables follow iso-lines of two value-noise fields. The hash is integer-based:
// the old sin() hash rounded differently on either side of a lattice line on some
// GPUs, which chopped every cable into offset pieces at the grid seams.

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
// The playable rectangle (x/z min, x/z max). Outside it the floor keeps going as the
// inaccessible office and fades into `outside_dark` over `outside_fade` metres.
uniform vec4 play_rect = vec4(-1000.0, -1000.0, 1000.0, 1000.0);
uniform vec4 outside_dark : source_color = vec4(0.1, 0.09, 0.14, 1.0);
uniform float outside_fade = 30.0;

varying vec3 wp;

float hash2(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(32768)) * uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	n ^= n >> 16u;
	return float(n) * (1.0 / 4294967295.0);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x),
			   mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Distance in metres from p to the 0.5 iso-line of a noise field (first-order:
// value offset over gradient length), so cables keep one width everywhere.
float cable_dist(vec2 p, float freq, vec2 seed, out float along, out float solid) {
	vec2 q = p * freq + seed;
	float n = vnoise(q);
	float e = 0.02;
	vec2 g = vec2(vnoise(q + vec2(e, 0.0)) - n, vnoise(q + vec2(0.0, e)) - n) / e * freq;
	along = vnoise(q * 0.37 + 11.0);
	// Near saddle points the iso-line pinches into a blob; the cable dips under the
	// floor there instead (solid fades to 0).
	float gl = length(g);
	solid = smoothstep(0.35 * freq, 0.6 * freq, gl);
	return abs(n - 0.5) / max(gl, 0.35 * freq);
}

// A rubber cable seen from above: rounded shading, a highlight, an ink rim and a
// soft contact shadow. Returns the colour mix amount in .a.
vec4 cable(float d, float w, vec3 col) {
	float t = d / w;
	float body = 1.0 - smoothstep(0.92, 1.0, t);
	float round_shade = sqrt(max(1.0 - t * t, 0.0));
	vec3 c = mix(col * 0.45, col, round_shade);
	c = mix(c, vec3(1.0), smoothstep(0.35, 0.0, abs(t - 0.35)) * 0.35 * body);
	float rim = smoothstep(0.82, 0.95, t) * body;
	c = mix(c, ink.rgb, rim);
	return vec4(c, body);
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
	vec3 glow = vec3(0.0);
	// Cables fade in with corruption (at full width: thin lines alias into dashes).
	float grow = smoothstep(0.15, 0.4, cor);
	if (grow > 0.0) {
		float along_a;
		float along_b;
		float solid_a;
		float solid_b;
		float da = cable_dist(wp.xz, 0.42, vec2(7.0, 3.0), along_a, solid_a);
		float db = cable_dist(wp.xz, 0.27, vec2(-41.0, 19.0), along_b, solid_b);
		float ga = grow * solid_a;
		float gb = grow * solid_b;
		float wa = 0.075;
		float wb = 0.05;
		// contact shadows first, so the cable that crosses on top shades the one below
		c *= 1.0 - 0.35 * (1.0 - smoothstep(wb, wb * 2.6, db)) * gb;
		c *= 1.0 - 0.35 * (1.0 - smoothstep(wa, wa * 2.6, da)) * ga;
		vec3 dark_col = mix(ink.rgb, seam_color.rgb, 0.35) * 1.6;
		vec4 cb = cable(db, wb, dark_col);
		c = mix(c, cb.rgb, cb.a * gb);
		vec4 ca = cable(da, wa, mix(corrupt_color.rgb * 0.55, ink.rgb, 0.25));
		c = mix(c, ca.rgb, ca.a * ga);
		// data pulses travel along the glowing cable; a soft halo hugs it
		float pulse = smoothstep(0.82, 1.0, sin(along_a * 90.0 - TIME * 3.5));
		float halo = (1.0 - smoothstep(wa, wa * 3.2, da)) * (1.0 - ca.a);
		glow += corrupt_color.rgb * (halo * (0.25 + 0.2 * sin(TIME * 2.0 + along_a * 30.0)) + ca.a * pulse * 1.6) * cor * ga;
	}
	// Glitch tiles: a scan-lined flicker instead of a solid slab.
	float glitch_tile = step(1.0 - cor * 0.04, hash2(id + vec2(floor(TIME * 3.0), 0.0)));
	float scan = step(0.5, fract(wp.z * 6.0 + TIME * 2.0));
	c = mix(c, corrupt_color.rgb, glitch_tile * (0.25 + 0.3 * scan) * smoothstep(0.0, 0.08, edge));
	// beyond the walls: the same office, dimmer the further it is from the play area
	vec2 outside = max(max(play_rect.xy - wp.xz, wp.xz - play_rect.zw), vec2(0.0));
	float away = smoothstep(0.0, outside_fade, length(outside));
	float dim = step(0.001, length(outside)) * (0.5 + 0.45 * away);
	c = mix(c, outside_dark.rgb, dim);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	EMISSION = (glow + corrupt_color.rgb * glitch_tile * 0.3 * scan) * (1.0 - away);
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
