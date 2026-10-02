uniform bool glow_enabled = false;
uniform bool linear_framebuffer = false;
uniform vec4 glow_tint : source_color = vec4(1.0);
uniform float glow_amount = 0.0;
uniform float glow_global = 1.0;
uniform bool glow_texture_enabled = false;
uniform bool glow_texture_constant = true;
uniform vec4 glow_texture_value = vec4(1.0);
uniform sampler2D glow_texture : source_color, filter_linear, repeat_disable;
uniform vec4 material_tint : source_color = vec4(1.0);
uniform float material_alpha = 1.0;
uniform bool hit_enabled = false;
uniform vec4 hit_tint : source_color = vec4(1.0);
uniform float hit_glow = 1.0;
uniform float hit_blend = 0.0;

vec4 original_renderer_sample(vec4 pixel, vec4 renderer_tint) {
	if (!linear_framebuffer) {
		// Decode the two colors separately before multiplication. Decoding their
		// sRGB product would change dark tints, especially near the transfer knee.
		pixel.rgb = original_to_linear(pixel.rgb);
		renderer_tint.rgb = original_to_linear(renderer_tint.rgb);
	}
	return pixel * renderer_tint;
}

vec4 original_hit_surface(vec4 pixel) {
	// The source hit-color blend precedes glow and material tint.
	if (hit_enabled) {
		vec3 hit_color = linear_framebuffer ? hit_tint.rgb : original_to_linear(hit_tint.rgb);
		pixel.rgb = mix(pixel.rgb, hit_color * hit_glow, hit_blend);
	}
	return pixel;
}

vec4 original_post_hit_surface(vec4 pixel, vec2 uv) {
	// Verified from the shipped GLOW_ON pixel program. Renderer alpha affects
	// colored emission quadratically; material tint and alpha are applied after it.
	if (glow_enabled) {
		vec3 glow_color = linear_framebuffer ? glow_tint.rgb : original_to_linear(glow_tint.rgb);
		if (glow_texture_enabled) {
			// GLOWTEX program 872: emission is independent of main RGB and
			// contains main alpha once, multiplied by the glow texture alpha.
			vec4 emission = glow_texture_constant ? glow_texture_value : texture(glow_texture, uv);
			if (!glow_texture_constant && !linear_framebuffer) {
				emission.rgb = original_to_linear(emission.rgb);
			}
			pixel.rgb = pixel.rgb * glow_global + emission.rgb * emission.a * pixel.a * glow_amount * glow_color;
		} else {
			pixel.rgb *= glow_global + pixel.a * pixel.a * glow_amount * glow_color;
		}
	}
	vec3 tint_color = linear_framebuffer ? material_tint.rgb : original_to_linear(material_tint.rgb);
	pixel *= vec4(tint_color, material_tint.a);
	pixel.a *= material_alpha;
	return pixel;
}

vec4 original_surface(vec4 pixel, vec2 uv) {
	return original_post_hit_surface(original_hit_surface(pixel), uv);
}
