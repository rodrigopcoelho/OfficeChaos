shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

// Inverted-hull ink outline, extruded in world space so scaled parts keep an even line.
// Uniform mode:  width/box_mode uniforms (box_mode extrudes along sign(VERTEX) for
//                hard-edged BoxMesh walls, otherwise along the normal).
// Vertex mode:   batched meshes (MeshBatcher) carry the line per vertex:
//                UV.x = width (negative = box mode), UV.y + UV2 = box extrusion dir.
//                A zero width collapses the vertex outside the view (no line).

uniform vec4 ink : source_color = vec4(0.12, 0.09, 0.16, 1.0);
uniform float width = 0.035;
uniform float box_mode = 0.0;
uniform float occlude_fade = 0.0;
uniform float vertex_mode = 0.0;

global uniform vec3 player_pos;

varying vec3 world_pos;

void vertex() {
	float w = width;
	bool boxed = box_mode > 0.5;
	vec3 dir_obj = boxed ? sign(VERTEX) : NORMAL;
	if (vertex_mode > 0.5) {
		w = abs(UV.x);
		boxed = UV.x < 0.0;
		dir_obj = boxed ? vec3(UV2.x, UV.y, UV2.y) : NORMAL;
	}
	vec3 wn = mat3(MODEL_MATRIX) * dir_obj;
	wn = boxed ? wn : normalize(wn);
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	wp.xyz += wn * w;
	world_pos = wp.xyz;
	POSITION = w > 0.0001 ? PROJECTION_MATRIX * VIEW_MATRIX * wp : vec4(2.0, 2.0, 2.0, 1.0);
}

void fragment() {
	ALBEDO = ink.rgb;
	if (occlude_fade > 0.5) {
		vec3 d = world_pos - player_pos;
		float limit = world_pos.y * 1.1 + 0.6;
		if (d.z > 0.1 && d.z < limit && abs(d.x) < 2.8 && world_pos.y > 0.9) {
			discard;
		}
	}
}
