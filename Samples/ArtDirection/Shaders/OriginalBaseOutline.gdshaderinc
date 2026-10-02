// Mat_Enemy 5, shipped pixel program 2625: four cardinal alpha samples.
uniform bool base_outline_enabled = false;
uniform vec4 base_outline_color : source_color = vec4(1.0);
uniform float base_outline_alpha = 0.0;
uniform float base_outline_glow = 1.0;
uniform int base_outline_pixel_width = 1;
uniform bool base_outline_pixel_perfect = true;
uniform float base_outline_width = 0.0;

vec4 original_outlined_surface(sampler2D source_texture, vec2 uv, vec4 pixel, float renderer_alpha) {
	pixel = original_hit_surface(pixel);
	if (base_outline_enabled) {
		// Mat_WeakTarget program 2605 scales texel size by OutlineWidth * 200.
		// Its non-pixel-perfect mode therefore allows fractional-pixel offsets.
		float width = base_outline_pixel_perfect ? float(base_outline_pixel_width) : base_outline_width * 200.0;
		vec2 step_uv = vec2(width) / vec2(textureSize(source_texture, 0));
		float neighbors = texture(source_texture, uv + vec2(step_uv.x, 0.0)).a;
		neighbors += texture(source_texture, uv - vec2(step_uv.x, 0.0)).a;
		neighbors += texture(source_texture, uv + vec2(0.0, step_uv.y)).a;
		neighbors += texture(source_texture, uv - vec2(0.0, step_uv.y)).a;
		float source_alpha = texture(source_texture, uv).a;
		float weight = (1.0 - source_alpha) * base_outline_alpha * step(0.05, clamp(neighbors, 0.0, 1.0));
		vec3 color = linear_framebuffer ? base_outline_color.rgb : original_to_linear(base_outline_color.rgb);
		vec4 outline = vec4(color * renderer_alpha * base_outline_glow, weight);
		// Native alpha is mixed with weight itself, so the new edge alpha is
		// weight squared. Replacing it with an ordinary opaque outline is brighter.
		pixel = mix(pixel, outline, weight);
	}
	return original_post_hit_surface(pixel, uv);
}
