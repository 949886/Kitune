shader_type canvas_item;
render_mode unshaded, blend_disabled;

// URP 2022.3 Bloom: bilinear prefilter, separable Gaussian, mip interpolation.
uniform sampler2D source_texture : filter_linear, repeat_disable;
uniform sampler2D low_texture : filter_linear, repeat_disable;
uniform int pass_mode = 0;
uniform float scatter = 0.68;
uniform float clamp_max = 65472.0;
uniform float threshold = 0.0;

const float WEIGHTS[5] = {0.22702703, 0.19459459, 0.12162162, 0.05405405, 0.01621622};

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(source_texture, 0));
	vec3 color = texture(source_texture, UV).rgb;

	if (pass_mode == 0) {
		color = min(color, vec3(clamp_max));
		float brightness = max(color.r, max(color.g, color.b));
		float knee = threshold * 0.5;
		float soft = clamp(brightness - threshold + knee, 0.0, 2.0 * knee);
		soft = soft * soft / (4.0 * knee + 0.0001);
		color *= max(brightness - threshold, soft) / max(brightness, 0.0001);
		color = max(color, vec3(0.0));
	} else if (pass_mode == 1) {
		color *= WEIGHTS[0];
		for (int tap = 1; tap <= 4; tap++) {
			vec2 offset = vec2(texel.x * 2.0 * float(tap), 0.0);
			color += (texture(source_texture, UV - offset).rgb
				+ texture(source_texture, UV + offset).rgb) * WEIGHTS[tap];
		}
	} else if (pass_mode == 2) {
		color *= WEIGHTS[0];
		vec2 inner = vec2(0.0, texel.y * 1.38461538);
		vec2 outer = vec2(0.0, texel.y * 3.23076923);
		color += (texture(source_texture, UV - inner).rgb
			+ texture(source_texture, UV + inner).rgb) * 0.31621622;
		color += (texture(source_texture, UV - outer).rgb
			+ texture(source_texture, UV + outer).rgb) * 0.07027027;
	} else {
		color = mix(color, texture(low_texture, UV).rgb, scatter);
	}
	COLOR = vec4(color, 1.0);
}
