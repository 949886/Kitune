// Explicit per-instance source offset/clipping, currently used by timer reels.
uniform bool source_uv_controls = false;
uniform vec2 source_uv_offset = vec2(0.0);
uniform vec4 source_uv_clip = vec4(0.0);
float original_source_clip(vec2 uv) {
    if (!source_uv_controls) return 1.0;
    vec2 p = vec2(uv.x, 1.0 - uv.y);
    return step(source_uv_clip.x, p.x) * step(p.x, 1.0 - source_uv_clip.y)
        * step(source_uv_clip.z, p.y) * step(p.y, 1.0 - source_uv_clip.w);
}

// UV operations from the shipped jade, factory, weakness and particle programs.
uniform bool uv_effects_enabled = false;
uniform bool distort_enabled = false;
uniform bool wave_enabled = false;
uniform bool round_wave_enabled = false;
uniform bool warp_enabled = false;
uniform bool wind_enabled = false;
uniform float grass_speed = 0.0;
uniform float grass_wind = 0.0;
uniform float grass_radial_bend = 0.0;
uniform bool pinch_enabled = false;
uniform bool pixelate_enabled = false;
uniform float pinch_amount = 0.0;
uniform float pixelate_size = 32.0;
uniform float warp_scale = 1.0;
uniform float warp_speed = 0.0;
uniform float warp_strength = 0.0;
uniform float warp_seed = 0.0;
uniform sampler2D distort_texture : filter_linear, repeat_enable;
uniform bool distort_srgb = true;
uniform vec4 main_texture_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 distort_texture_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec2 distort_speed = vec2(0.0);
uniform float distort_amount = 0.0;
uniform vec2 wave_center = vec2(0.0);
uniform float wave_amount = 0.0;
uniform float wave_speed = 0.0;
uniform float wave_strength = 0.0;
uniform float round_wave_speed = 0.0;
uniform float round_wave_strength = 0.0;
// Negative selects the runtime clock; a fixed clock supports source comparisons.
uniform float uv_effect_time = -1.0;

vec2 original_signed_fraction(vec2 value) {
	return sign(value) * fract(abs(value));
}

float original_pinch_atan(float value) {
	// Exact float constants from the shipped DXBC atan approximation.
	float x = min(abs(value), 1.0) / max(abs(value), 1.0);
	float square = x * x;
	float polynomial = square * 0.02083509974181652 - 0.08513300120830536;
	polynomial = square * polynomial + 0.18014100193977356;
	polynomial = square * polynomial - 0.3302994966506958;
	polynomial = square * polynomial + 0.9998660087585449;
	float result = x * polynomial;
	if (abs(value) > 1.0) {
		result = 1.5707963705062866 - result;
	}
	return value < 0.0 ? -result : result;
}

float original_noise_texel(ivec2 point, ivec2 size) {
	point = ((point % size) + size) % size;
	float value = texelFetch(distort_texture, point, 0).r;
	return distort_srgb ? original_to_linear(vec3(value)).r : value;
}

float original_noise_sample(vec2 uv) {
	// The source sRGB texture is decoded before bilinear filtering. Doing the
	// conversion after texture() changes the displacement, especially in shadows.
	ivec2 size = textureSize(distort_texture, 0);
	vec2 point = fract(uv) * vec2(size) - 0.5;
	ivec2 base = ivec2(floor(point));
	vec2 weight = fract(point);
	float top = mix(original_noise_texel(base, size), original_noise_texel(base + ivec2(1, 0), size), weight.x);
	float bottom = mix(original_noise_texel(base + ivec2(0, 1), size), original_noise_texel(base + ivec2(1, 1), size), weight.x);
	return mix(top, bottom, weight.y);
}

vec2 original_effect_uv(vec2 godot_uv, vec2 texture_size, float aspect, float runtime_time) {
	if (!uv_effects_enabled) {
		return source_uv_controls ? fract(godot_uv + vec2(source_uv_offset.x, -source_uv_offset.y)) : godot_uv;
	}
	float time = uv_effect_time < 0.0 ? runtime_time : uv_effect_time;
	vec2 source_uv = vec2(godot_uv.x, 1.0 - godot_uv.y);
	vec2 original_uv = source_uv * main_texture_st.xy + main_texture_st.zw;
	vec2 uv = original_uv;
	if (warp_enabled) {
		// Weakness program 2634: divide by MainTex_ST scale before the sine.
		// _RandomSeed is an instance time offset, not a spatial noise value.
		vec2 phase = uv / main_texture_st.xy * 6.28318530718 / warp_scale;
		uv += sin(phase + vec2((time + warp_seed) * warp_speed)) * warp_strength;
	}
	if (distort_enabled) {
		// Unity _Time.x runs at one twentieth of _Time.y. Preserve signed fmod.
		vec2 noise_uv = source_uv * distort_texture_st.xy + distort_texture_st.zw;
		noise_uv += original_signed_fraction(time / 20.0 * distort_speed);
		float value = original_noise_sample(vec2(noise_uv.x, 1.0 - noise_uv.y));
		uv += vec2((value - 0.5) * 0.2 * distort_amount);
	}
	if (wave_enabled) {
		vec2 direction = original_signed_fraction(wave_center * main_texture_st.xy - uv);
		direction.x *= aspect;
		uv += direction * sin(length(direction) * wave_amount - time * wave_speed) * wave_strength * 0.001;
	}
	if (round_wave_enabled) {
		// Radius uses the original UVs, not the coordinates already displaced above.
		vec2 radius = main_texture_st.xy * 0.5 - original_uv;
		radius.y *= texture_size.y / texture_size.x;
		float wave = sin((time * round_wave_speed * 0.1 - length(radius)) * 66.666672);
		uv += vec2(wave * round_wave_strength * 0.1);
	}
	if (wind_enabled) {
		// Native factory program 2632: WIND operates on fragment UVs. Its phase
		// uses _Time.x * 10, and sway is weighted by the original transformed V.
		float sway = sin(time / 20.0 * grass_speed * 10.0);
		uv.x += original_uv.y * sway * grass_wind * 0.01;
		// The compiled program takes the fraction of abs(U), including negative U.
		uv.x = fract(abs(uv.x));
		vec2 radial = uv - vec2(0.5, 0.1);
		uv += vec2(radial.y, -radial.x) * dot(radial, radial) * sway * grass_radial_bend;
	}
	if (pinch_enabled) {
		vec2 center = main_texture_st.xy * 0.5;
		vec2 radial = uv - center;
		float radius = length(radial);
		float coefficient = (0.001 - pinch_amount) * 3.141592025756836 / length(center);
		// The shipped variant normalizes this radial direction. At the exact
		// center its continuous limit is the center itself.
		if (radius > 0.0) {
			uv = center + radial / radius * 0.5 * original_pinch_atan(-10.0 * coefficient * radius) / original_pinch_atan(-5.0 * coefficient);
		}
	}
	if (pixelate_enabled) {
		vec2 grid = vec2(pixelate_size, pixelate_size * texture_size.y / texture_size.x);
		uv = floor(uv * grid) / grid;
	}
	return vec2(uv.x, 1.0 - uv.y);
}
