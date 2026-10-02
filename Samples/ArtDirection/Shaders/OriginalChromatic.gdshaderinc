// URP UberPost: radial RGB separation before bloom and post-exposure.
vec3 original_chromatic(sampler2D source, vec2 uv, float amount) {
	vec2 radial = 2.0 * uv - 1.0;
	vec2 step_uv = -radial * dot(radial, radial) * amount / 3.0;
	return vec3(
		texture(source, uv).r,
		texture(source, uv + step_uv).g,
		texture(source, uv + 2.0 * step_uv).b
	);
}
