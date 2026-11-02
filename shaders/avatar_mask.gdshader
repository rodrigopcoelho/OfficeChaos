shader_type canvas_item;

// Round profile picture: clips a square portrait to an anti-aliased circle.

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float d = length(UV - 0.5) * 2.0;
	float edge = fwidth(d) * 1.5;
	COLOR = vec4(c.rgb, c.a * (1.0 - smoothstep(1.0 - edge, 1.0, d)));
}
