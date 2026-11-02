shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

#include "res://shaders/toon_light.gdshaderinc"

// Flat illustrated look: flat albedo with the shared toon lighting (toon_light.gdshaderinc).
// vertex_colors = 1 is used by batched meshes (MeshBatcher): albedo comes from
// COLOR.rgb and emission energy from COLOR.a * 4, so many parts share one draw call.

uniform vec4 albedo : source_color = vec4(0.9, 0.85, 0.75, 1.0);
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float occlude_fade = 0.0;
uniform float vertex_colors = 0.0;

global uniform vec3 player_pos;

varying vec3 world_pos;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + vec3(0.055)) / vec3(1.055), vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 alb = albedo.rgb;
	vec3 em = emission.rgb * emission_energy;
	if (vertex_colors > 0.5) {
		alb = COLOR.rgb;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
		alb = srgb_to_linear(alb);
#endif
		em = alb * COLOR.a * 4.0;
	}
	ALBEDO = alb;
	ROUGHNESS = 1.0;
	EMISSION = em;
	if (occlude_fade > 0.5) {
		vec3 d = world_pos - player_pos;
		float limit = world_pos.y * 1.1 + 0.6;
		if (d.z > 0.1 && d.z < limit && abs(d.x) < 2.8 && world_pos.y > 0.9) {
			if (mod(floor(FRAGCOORD.x) + floor(FRAGCOORD.y), 2.0) < 1.0 || mod(floor(FRAGCOORD.y), 3.0) < 1.0) {
				discard;
			}
		}
	}
}
