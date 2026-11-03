shader_type canvas_item;

// Full-screen "late-90s anime on a CRT" pass: soft film grain, gentle scanlines,
// vignette, chromatic aberration and glitch slices.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float aberration = 0.0;
uniform float glitch = 0.0;
uniform float vignette = 0.35;
uniform float scanline = 0.05;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float damage = 0.0;
uniform float grain = 0.035;

float rnd(float x) {
	return fract(sin(x * 12.9898) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = floor(TIME * 14.0);
	float row = floor(uv.y * 36.0);
	float r = rnd(row + t * 7.13);
	if (r < glitch * 0.22) {
		uv.x += (rnd(row * 3.1 + t) - 0.5) * 0.06 * glitch;
	}
	float ab = aberration * 0.006 + glitch * 0.0025;
	vec3 col;
	col.r = texture(screen_tex, uv + vec2(ab, 0.0)).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - vec2(ab, 0.0)).b;
	col *= 1.0 - scanline * (0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159));
	// film grain: per-pixel noise re-rolled 24 times a second, strongest in midtones
	uvec3 q = uvec3(uvec2(FRAGCOORD.xy), uint(TIME * 24.0)) * uvec3(1597334673u, 3812015801u, 2798796415u);
	uint h = (q.x ^ q.y ^ q.z) * 1597334673u;
	h ^= h >> 15u;
	float n = float(h) * (1.0 / 4294967295.0) - 0.5;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col += n * grain * (1.0 - abs(lum - 0.5) * 1.2);
	vec2 d = SCREEN_UV - 0.5;
	float v = dot(d, d);
	col *= 1.0 - vignette * v * 2.2;
	col = mix(col, vec3(0.75, 0.05, 0.08), damage * smoothstep(0.08, 0.45, v) * 0.75);
	col *= tint.rgb;
	COLOR = vec4(col, 1.0);
}
