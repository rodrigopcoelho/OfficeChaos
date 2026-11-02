// Shared toon lighting for toon.gdshader and character.gdshader: one hard step for
// the sun (the shadow colour is the environment's ambient tint) and stepped colour
// pools from point lights.

uniform float shade_softness = 0.04;
uniform float light_wrap = 0.0;  // > 0 moves the sun's shadow edge around the back (faces)

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		float ndl = dot(NORMAL, LIGHT);
		float shadow = smoothstep(0.3, 0.45, ATTENUATION);
		if (light_wrap > 0.0) {
			// Wrapped surfaces that face away from the sun would only see their own shadow.
			shadow = mix(1.0, shadow, smoothstep(0.0, 0.3, ndl));
		}
		float lit = smoothstep(-light_wrap, shade_softness - light_wrap, ndl) * shadow;
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * lit;
	} else {
		float wrap = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
		float a = ATTENUATION * wrap;
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * smoothstep(0.2, 0.23, a) * 0.22;
	}
}
