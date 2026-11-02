shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

#include "res://shaders/toon_light.gdshaderinc"

// Character skin: the flat toon look of toon.gdshader plus details painted in object
// space, the way Animal Crossing paints faces and clothes onto simple shapes.
//   paint_mode 1 (face), on the "head" kit mesh: eyes, lashes, brows, blush, nose,
//       mouth and glasses. `blink` and `mood` are animated by CharacterVisual.
//   paint_mode 2 (suit), on the "blazer" kit mesh: shirt V, tie, lapels, buttons,
//       pockets and a clip-on ID badge.
// Coordinates are the kit mesh's unit box (x = the character's right, y up, -z = front)
// projected onto the front. `aspect` (size.y / size.x) keeps circles round.

uniform vec4 albedo : source_color = vec4(0.93, 0.78, 0.64, 1.0);
uniform int paint_mode = 1;
uniform float aspect = 1.0;
uniform vec4 ink : source_color = vec4(0.13, 0.09, 0.12, 1.0);
uniform vec4 white : source_color = vec4(1.0, 0.99, 0.96, 1.0);

// Face (positions and sizes in head widths, measured from the head's centre)
uniform vec4 iris_color : source_color = vec4(0.17, 0.11, 0.09, 1.0);
uniform vec4 blush_color : source_color = vec4(1.0, 0.45, 0.5, 1.0);
uniform vec4 mouth_color : source_color = vec4(0.62, 0.18, 0.22, 1.0);
uniform vec4 glasses_color : source_color = vec4(0.16, 0.13, 0.2, 1.0);
uniform vec2 eye_pos = vec2(0.17, 0.0);     // x: distance from the centre line, y: height
uniform vec2 eye_size = vec2(0.065, 0.085); // radii
uniform float sclera = 0.0;    // 1 = white eyes with a coloured iris, 0 = solid dark eyes
uniform float iris = 0.8;      // iris radius / eye height (sclera eyes)
uniform float shine = 0.34;    // highlight radius / eye width (0 = none)
uniform float lid = 0.0;       // upper lid: 0 open .. 0.6 half-closed (sleepy)
uniform float lash = 0.0;      // upper lash line thickness (0 = none)
uniform float flick = 0.0;     // outer lash flick (0 / 1)
uniform float brow = 0.0;      // brow thickness (0 = none)
uniform float brow_y = 0.13;   // brow height above the eye centre
uniform float brow_tilt = 0.0; // > 0 frowning, < 0 worried
uniform int mouth = 0;         // 0 smile, 1 cat, 2 open smile, 3 flat, 4 grin
uniform float mouth_y = -0.17;
uniform float mouth_w = 0.055;
uniform float blush = 0.5;
uniform float nose = 1.0;
uniform float freckles = 0.0;
uniform int glasses = 0;       // 0 none, 1 round, 2 square
uniform float bags = 0.0;      // tired eye bags
uniform float blink = 0.0;     // 0 open .. 1 closed
uniform int mood = 0;          // 0 neutral, 1 happy, 2 hurt, 3 knocked out

// Suit (in blazer units: the body spans -0.5..0.5 on both axes)
uniform vec4 shirt_color : source_color = vec4(0.96, 0.95, 0.92, 1.0);
uniform vec4 tie_color : source_color = vec4(0.55, 0.15, 0.18, 1.0);
uniform vec4 badge_color : source_color = vec4(0.31, 0.82, 0.69, 1.0);
uniform float v_bottom = -0.04; // where the jacket's V opening closes
uniform float badge = 1.0;

varying vec3 lp;

float cover(float d, float aa) {
	return clamp(0.5 - d / aa, 0.0, 1.0);
}

float sd_ellipse(vec2 q, vec2 r) {
	return (length(q / r) - 1.0) * min(r.x, r.y);
}

float sd_seg(vec2 q, vec2 a, vec2 b) {
	vec2 qa = q - a;
	vec2 ba = b - a;
	return length(qa - ba * clamp(dot(qa, ba) / dot(ba, ba), 0.0, 1.0));
}

float sd_round_box(vec2 q, vec2 b, float r) {
	vec2 d = abs(q) - b + r;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

// A "U" curve of half-width w with its ends on q.y = 0 (ap = how round: 0..PI/2).
float sd_cup(vec2 q, float w, float ap) {
	float r = w / sin(ap);
	q.y -= r * cos(ap);
	q = vec2(abs(q.x), -q.y);
	vec2 sc = vec2(sin(ap), cos(ap));
	return (sc.y * q.x > sc.x * q.y) ? length(q - sc * r) : abs(length(q) - r);
}

vec3 paint_eye(vec3 col, vec2 p, float s, float aa) {
	vec2 r = eye_size;
	vec2 q = p - vec2(eye_pos.x * s, eye_pos.y);
	float t = max(0.012, aa * 0.7);
	if (mood == 1) {
		// happy: ^ ^
		float d = sd_cup(vec2(q.x, -q.y - r.y * 0.25), r.x * 0.95, 1.15) - t;
		return mix(col, ink.rgb, cover(d, aa));
	}
	if (mood == 2) {
		// hurt: > <
		vec2 tip = vec2(-s * r.x * 0.6, 0.0);
		float d = min(sd_seg(q, tip, vec2(s * r.x * 0.6, r.y * 0.6)), sd_seg(q, tip, vec2(s * r.x * 0.6, -r.y * 0.6))) - t;
		return mix(col, ink.rgb, cover(d, aa));
	}
	if (mood == 3) {
		// knocked out: x x
		float k = r.x * 0.7;
		float d = min(sd_seg(q, vec2(-k, -k), vec2(k, k)), sd_seg(q, vec2(-k, k), vec2(k, -k))) - t;
		return mix(col, ink.rgb, cover(d, aa));
	}
	float l = mix(lid, 1.0, blink);
	float h = r.y * (1.0 - 1.25 * l);          // lid line height
	float d_eye = max(sd_ellipse(q, r), q.y - h);
	float open = 1.0 - smoothstep(0.75, 0.95, l);
	if (bags > 0.0) {
		float db = sd_cup(q + vec2(0.0, r.y * 1.2), r.x * 0.8, 0.9) - t * 0.5;
		col = mix(col, ink.rgb, cover(db, aa) * 0.35 * bags);
	}
	if (sclera > 0.5) {
		col = mix(col, white.rgb, cover(d_eye, aa) * open);
		vec2 ic = vec2(0.0, -r.y * 0.08);
		vec2 ir = vec2(r.x * 0.86, r.y * iris);
		float d_iris = max(sd_ellipse(q - ic, ir), d_eye);
		vec3 ic_col = mix(iris_color.rgb, iris_color.rgb * 1.7 + 0.06, smoothstep(0.0, -ir.y, q.y - ic.y));
		col = mix(col, ic_col, cover(d_iris, aa) * open);
		float d_pupil = max(sd_ellipse(q - ic, ir * 0.48), d_eye);
		col = mix(col, ink.rgb, cover(d_pupil, aa) * open);
	} else {
		col = mix(col, iris_color.rgb, cover(d_eye, aa) * open);
	}
	if (shine > 0.0) {
		float d_h = max(length(q - vec2(r.x * 0.3, r.y * 0.36)) - r.x * shine, d_eye);
		float d_h2 = max(length(q - vec2(-r.x * 0.32, -r.y * 0.42)) - r.x * shine * 0.48, d_eye);
		col = mix(col, white.rgb, cover(min(d_h, d_h2), aa) * open);
	}
	// Upper lash line: the top of the visible eye, tapering down its sides. Closed
	// eyes keep only this line.
	float tl = max(lash, 0.014 * smoothstep(0.45, 0.9, l));
	if (tl > 0.0) {
		float y0 = min(h, r.y * 0.1);
		float taper = smoothstep(y0 - r.y * 0.45, y0 + r.y * 0.25, q.y);
		float w = max(tl * taper, 0.0001);
		float d_l = abs(d_eye - w * 0.5) - w * 0.5;
		col = mix(col, ink.rgb, cover(d_l, aa) * step(0.0005, tl * taper));
		if (flick > 0.0) {
			vec2 a = vec2(s * r.x * 0.82, min(h, r.y * 0.5));
			float d_f = sd_seg(q, a, a + vec2(s * r.x * 0.5, r.y * 0.3)) - tl * 0.6;
			col = mix(col, ink.rgb, cover(d_f, aa));
		}
	}
	return col;
}

vec3 paint_brow(vec3 col, vec2 p, float s, float aa) {
	float th = brow;
	float tilt = brow_tilt;
	if (mood == 2) {
		th = max(th, 0.013);
		tilt = -0.9;
	}
	if (th <= 0.0 || mood == 1 || mood == 3) {
		return col;
	}
	vec2 b = vec2(eye_pos.x * s, eye_pos.y + brow_y);
	float w = eye_size.x * 0.85;
	vec2 inner = b + vec2(-s * w, -tilt * 0.03);
	vec2 outer = b + vec2(s * w, tilt * 0.03);
	float d = sd_seg(p, inner, outer) - max(th, aa * 0.6);
	return mix(col, ink.rgb, cover(d, aa));
}

vec3 paint_mouth(vec3 col, vec2 p, float aa) {
	vec2 m = p - vec2(0.0, mouth_y);
	float w = mouth_w;
	float t = max(0.011, aa * 0.7);
	int kind = mouth;
	if (mood == 1) {
		kind = 2;
		w *= 1.25;
	} else if (mood == 2) {
		kind = 5;
	} else if (mood == 3) {
		kind = 6;
	}
	if (kind == 2 || kind == 4) {
		// open smile "D" (grin: wider, with teeth)
		vec2 rr = kind == 4 ? vec2(w * 1.3, w * 0.85) : vec2(w, w * 0.95);
		float d_o = max(sd_ellipse(m, rr), m.y);
		col = mix(col, mouth_color.rgb, cover(d_o, aa));
		if (kind == 4) {
			col = mix(col, white.rgb, cover(max(d_o, -m.y - rr.y * 0.32), aa));
		} else {
			float d_t = max(sd_ellipse(m - vec2(0.0, -rr.y * 0.78), vec2(rr.x * 0.55, rr.y * 0.4)), d_o);
			col = mix(col, blush_color.rgb, cover(d_t, aa));
		}
		return mix(col, ink.rgb, cover(abs(d_o) - t * 0.45, aa));
	}
	if (kind == 5) {
		// hurt: small open "o"
		float d_o = sd_ellipse(m - vec2(0.0, -0.01), vec2(w * 0.55, w * 0.5));
		col = mix(col, mouth_color.rgb, cover(d_o, aa));
		return mix(col, ink.rgb, cover(abs(d_o) - t * 0.45, aa));
	}
	float d;
	if (kind == 1) {
		d = min(sd_cup(m + vec2(w * 0.5, 0.0), w * 0.5, 1.3), sd_cup(m - vec2(w * 0.5, 0.0), w * 0.5, 1.3));
	} else if (kind == 3) {
		d = sd_seg(m, vec2(-w * 0.7, 0.0), vec2(w * 0.7, 0.0));
	} else if (kind == 6) {
		d = max(abs(m.y - 0.012 * sin(m.x / w * 6.2832)), abs(m.x) - w * 0.9);
	} else {
		d = sd_cup(m, w, 0.95);
	}
	return mix(col, ink.rgb, cover(d - t, aa));
}

vec3 paint_glasses(vec3 col, vec2 p, float aa) {
	float r = max(eye_size.x, eye_size.y) * 1.45;
	float gt = max(0.009, aa * 0.6);
	float d = 1e3;
	float lens = 1e3;
	for (int i = 0; i < 2; i++) {
		float s = i == 0 ? -1.0 : 1.0;
		vec2 q = p - vec2(eye_pos.x * s, eye_pos.y - 0.005);
		float ring = glasses == 2 ? sd_round_box(q, vec2(r * 1.12, r * 0.82), r * 0.3) : length(q) - r;
		lens = min(lens, ring);
		d = min(d, abs(ring) - gt);
		d = min(d, sd_seg(p, vec2(s * (eye_pos.x + r * (glasses == 2 ? 1.12 : 1.0)), eye_pos.y + 0.01), vec2(s * 0.5, eye_pos.y + 0.03)) - gt);
	}
	float inner = eye_pos.x - r * (glasses == 2 ? 1.12 : 1.0);
	d = min(d, sd_seg(p, vec2(-inner, eye_pos.y + 0.012), vec2(inner, eye_pos.y + 0.012)) - gt);
	col = mix(col, white.rgb, cover(lens, aa) * 0.16);
	return mix(col, glasses_color.rgb, cover(d, aa));
}

vec3 paint_face(vec3 skin, vec2 p, float aa) {
	vec3 col = skin;
	if (nose > 0.0) {
		vec2 nq = p - vec2(0.0, mix(eye_pos.y, mouth_y, 0.55));
		col = mix(col, skin * vec3(0.86, 0.72, 0.7), cover(sd_ellipse(nq, vec2(0.018, 0.012)), aa) * nose);
	}
	float bl = blush * (mood == 1 ? 1.4 : 1.0);
	for (int i = 0; i < 2; i++) {
		float s = i == 0 ? -1.0 : 1.0;
		vec2 c = vec2(s * (eye_pos.x + 0.065), eye_pos.y - eye_size.y - 0.05);
		col = mix(col, blush_color.rgb, cover(sd_ellipse(p - c, vec2(0.062, 0.034)), aa * 4.0) * bl * 0.6);
		if (freckles > 0.0) {
			float df = min(min(length(p - c - vec2(-0.026, 0.008)), length(p - c - vec2(0.0, -0.01))), length(p - c - vec2(0.026, 0.006))) - 0.008;
			col = mix(col, skin * vec3(0.62, 0.45, 0.38), cover(df, aa) * freckles);
		}
	}
	col = paint_mouth(col, p, aa);
	col = paint_eye(col, p, -1.0, aa);
	col = paint_eye(col, p, 1.0, aa);
	if (glasses > 0) {
		col = paint_glasses(col, p, aa);
	}
	col = paint_brow(col, p, -1.0, aa);
	col = paint_brow(col, p, 1.0, aa);
	return col;
}

vec3 paint_suit(vec3 base, vec2 u, float aa) {
	vec3 col = base;
	float t = max(0.011, aa * 0.7);
	// Open V of the jacket with a lapel band along each edge.
	float k = 0.16 / (0.5 - v_bottom);
	float d_v = (abs(u.x) - (u.y - v_bottom) * k) * inversesqrt(1.0 + k * k);
	float lw = 0.075;
	float above = smoothstep(v_bottom - 0.03, v_bottom + 0.05, u.y);
	col = mix(col, base * 0.78, cover(max(d_v - lw, -d_v), aa) * above);
	// Shirt and tie inside the V.
	float in_v = cover(d_v, aa);
	col = mix(col, shirt_color.rgb, in_v);
	float knot_y = 0.38;
	float half_w = u.y > knot_y ? 0.042 : 0.03 + (knot_y - u.y) * 0.12;
	float d_tie = abs(u.x) - half_w;
	col = mix(col, tie_color.rgb, cover(d_tie, aa) * in_v);
	col = mix(col, ink.rgb, cover(abs(u.y - knot_y) - t * 0.4, aa) * cover(d_tie, aa) * in_v);
	// Ink lines: V edges, lapel edges, front closure.
	col = mix(col, ink.rgb, cover(abs(d_v) - t * 0.5, aa) * step(v_bottom - 0.005, u.y));
	col = mix(col, ink.rgb, cover(abs(d_v - lw) - t * 0.5, aa) * above);
	col = mix(col, ink.rgb, cover(max(abs(u.x) - t * 0.5, u.y - v_bottom), aa));
	// Buttons on the closure.
	vec2 pb = vec2(u.x, u.y * aspect);
	float d_b = min(length(pb - vec2(0.0, (v_bottom - 0.1) * aspect)), length(pb - vec2(0.0, (v_bottom - 0.26) * aspect))) - 0.024;
	col = mix(col, ink.rgb, cover(d_b, aa));
	// Breast pocket with a pocket square on the left (-x), hip pocket flaps.
	float tri = abs(fract((u.x + 0.29) / 0.045) * 2.0 - 1.0);
	float d_sq = max(max(0.13 - u.y, u.y - (0.2 - 0.035 * tri)), max(-0.29 - u.x, u.x + 0.2));
	col = mix(col, white.rgb, cover(d_sq, aa));
	col = mix(col, ink.rgb, cover(sd_seg(u, vec2(-0.31, 0.13), vec2(-0.16, 0.13)) - t * 0.5, aa));
	col = mix(col, ink.rgb, cover(sd_seg(vec2(abs(u.x), u.y), vec2(0.2, -0.25), vec2(0.37, -0.25)) - t * 0.5, aa));
	// Clip-on ID badge on the right lapel.
	if (badge > 0.0) {
		vec2 bq = u - vec2(0.245, 0.06);
		float d_card = sd_round_box(bq, vec2(0.055, 0.075), 0.015);
		col = mix(col, white.rgb, cover(d_card, aa));
		col = mix(col, badge_color.rgb, cover(max(d_card, -(bq.y - 0.03)), aa));
		col = mix(col, ink.rgb * 1.5, cover(sd_round_box(bq - vec2(-0.02, -0.02), vec2(0.018, 0.022), 0.004), aa));
		col = mix(col, ink.rgb, cover(abs(d_card) - t * 0.4, aa));
	}
	return col;
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec3 col = albedo.rgb;
	vec2 p = vec2(lp.x, lp.y * aspect);
	float aa = max(length(fwidth(p)), 0.0001);
	if (paint_mode == 1) {
		float front = smoothstep(-0.12, -0.26, lp.z);
		col = mix(col, paint_face(col, p, aa), front);
	} else if (paint_mode == 2) {
		float front = smoothstep(-0.1, -0.24, lp.z);
		col = mix(col, paint_suit(col, lp.xy, max(length(fwidth(lp.xy)), 0.0001)), front);
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
