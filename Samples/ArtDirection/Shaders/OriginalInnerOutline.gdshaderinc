uniform bool inner_outline_enabled = false;
uniform float inner_outline_thickness = 1.0;
uniform float inner_outline_alpha = 1.0;
uniform float inner_outline_glow = 1.0;
uniform vec4 inner_outline_color : source_color = vec4(1.0);

vec3 original_outline_sample(sampler2D source_texture, vec2 uv) {
	vec3 color = texture(source_texture, uv).rgb;
	return linear_framebuffer ? color : original_to_linear(color);
}

vec4 original_inner_outline(sampler2D source_texture, vec2 uv, vec4 pixel) {
	if (!inner_outline_enabled) {
		return pixel;
	}
	// Shipped INNEROUTLINE_ON uses RGB differences, not an alpha silhouette.
	// Thickness is truncated to integer texels before the four neighbouring reads.
	vec2 offset = trunc(inner_outline_thickness) / vec2(textureSize(source_texture, 0));
	vec3 right = original_outline_sample(source_texture, uv + vec2(offset.x, 0.0));
	vec3 left = original_outline_sample(source_texture, uv - vec2(offset.x, 0.0));
	vec3 up = original_outline_sample(source_texture, uv + vec2(0.0, offset.y));
	vec3 down = original_outline_sample(source_texture, uv - vec2(0.0, offset.y));
	vec3 difference = 0.5 * (abs(right - left) + abs(up - down));
	float edge = length(difference * pixel.a * inner_outline_alpha);
	vec3 color = linear_framebuffer ? inner_outline_color.rgb : original_to_linear(inner_outline_color.rgb);
	pixel.rgb += edge * color * inner_outline_glow;
	return pixel;
}
