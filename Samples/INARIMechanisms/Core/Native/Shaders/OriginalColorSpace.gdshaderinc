// Keep the sRGB transfer at framebuffer boundaries; HDR light math stays linear.
vec3 original_to_linear(vec3 value) {
	vec3 low = value / 12.92;
	vec3 high = pow((value + 0.055) / 1.055, vec3(2.4));
	return mix(low, high, step(vec3(0.04045), value));
}

vec3 original_to_srgb(vec3 value) {
	value = max(value, vec3(0.0));
	vec3 low = value * 12.92;
	vec3 high = 1.055 * pow(value, vec3(1.0 / 2.4)) - 0.055;
	return mix(low, high, step(vec3(0.0031308), value));
}
