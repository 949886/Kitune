// Mat_SavePoint's shipped CHANGECOLOR_ON pixel program, before glow and material tint.
uniform bool color_change_enabled = false;
uniform vec4 color_change_target : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform vec4 color_change_new_color : source_color = vec4(1.0);
uniform float color_change_tolerance = 0.25;
uniform float color_change_luminosity = 0.0;

vec4 original_color_change(vec4 pixel) {
	if (!color_change_enabled) {
		return pixel;
	}
	vec3 target = linear_framebuffer
		? color_change_target.rgb
		: original_to_linear(color_change_target.rgb);
	vec3 replacement = linear_framebuffer
		? color_change_new_color.rgb
		: original_to_linear(color_change_new_color.rgb);
	vec3 difference = abs(pixel.rgb - target);
	float similarity = 1.0 - min(difference.r + difference.g + difference.b, 1.0);
	// DXBC uses sign/max: equality must keep the original pixel, unlike step().
	if (similarity > color_change_tolerance) {
		float luminosity = clamp(
			dot(pixel.rgb, vec3(0.3, 0.59, 0.11)) + color_change_luminosity,
			0.0,
			1.0
		);
		pixel.rgb = luminosity * replacement;
	}
	return pixel;
}
