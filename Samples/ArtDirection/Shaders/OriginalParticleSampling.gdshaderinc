// The native pixelring HD blur has an asymmetric nine-tap schedule: its
// (+x,-y) source corner is used twice and (+x,+y) is absent. Do not symmetrize.
uniform bool particle_blur_enabled = false;
uniform float particle_blur_intensity = 0.0;
uniform bool source_bilinear = false;

vec4 original_particle_blur_texel(sampler2D source, ivec2 point) {
	ivec2 bounds = textureSize(source, 0) - ivec2(1);
	vec4 pixel = texelFetch(source, clamp(point, ivec2(0), bounds), 0);
	pixel.rgb = original_to_linear(pixel.rgb);
	return pixel;
}

vec4 original_particle_blur_tap(sampler2D source, vec2 uv) {
	if (linear_framebuffer) {
		return texture(source, uv);
	}
	// Compatibility does not decode an sRGB sampler before filtering. Recover
	// the native linear interpolation explicitly before averaging blur taps.
	vec2 point = uv * vec2(textureSize(source, 0)) - 0.5;
	ivec2 base = ivec2(floor(point));
	vec2 weight = fract(point);
	vec4 top = mix(original_particle_blur_texel(source, base), original_particle_blur_texel(source, base + ivec2(1, 0)), weight.x);
	vec4 bottom = mix(original_particle_blur_texel(source, base + ivec2(0, 1)), original_particle_blur_texel(source, base + ivec2(1, 1)), weight.x);
	return mix(top, bottom, weight.y);
}

vec4 original_particle_sample(sampler2D source, vec2 uv, vec4 renderer_tint) {
	if (!particle_blur_enabled) {
		if (source_bilinear) {
			vec4 pixel = original_particle_blur_tap(source, uv);
			if (!linear_framebuffer) {
				renderer_tint.rgb = original_to_linear(renderer_tint.rgb);
			}
			return pixel * renderer_tint;
		}
		return original_renderer_sample(texture(source, uv), renderer_tint);
	}
	// 1/256 is a shader constant, independent of the imported texture size.
	float distance = particle_blur_intensity / 256.0;
	vec4 pixel = original_particle_blur_tap(source, uv + vec2(-distance, distance));
	pixel += 2.0 * original_particle_blur_tap(source, uv + vec2(-distance, 0.0));
	pixel += original_particle_blur_tap(source, uv + vec2(-distance, -distance));
	pixel += 2.0 * original_particle_blur_tap(source, uv + vec2(0.0, distance));
	pixel += 4.0 * original_particle_blur_tap(source, uv);
	pixel += 2.0 * original_particle_blur_tap(source, uv + vec2(0.0, -distance));
	pixel += 2.0 * original_particle_blur_tap(source, uv + vec2(distance, distance));
	pixel += 2.0 * original_particle_blur_tap(source, uv + vec2(distance, 0.0));
	if (!linear_framebuffer) {
		renderer_tint.rgb = original_to_linear(renderer_tint.rgb);
	}
	return pixel * renderer_tint / 16.0;
}
