shader_type canvas_item;
render_mode unshaded;

#include "res://Samples/ArtDirection/Shaders/OriginalColorSpace.gdshaderinc"
#include "res://Samples/ArtDirection/Shaders/OriginalWaterUV.gdshaderinc"

uniform sampler2D water_texture : repeat_disable, filter_nearest;
uniform bool linear_framebuffer = false;

vec3 reflection_texel(ivec2 pixel, ivec2 dimensions) {
	// Decode ARGB32 sRGB texels before interpolation on every rendering backend.
	ivec2 location = clamp(pixel, ivec2(0), dimensions - ivec2(1));
	return original_to_linear(texelFetch(water_texture, location, 0).rgb);
}

vec3 reflection_sample(vec2 uv) {
	ivec2 dimensions = textureSize(water_texture, 0);
	vec2 pixel = vec2(uv.x, 1.0 - uv.y) * vec2(dimensions) - vec2(0.5);
	ivec2 base = ivec2(floor(pixel));
	vec2 blend = fract(pixel);
	vec3 top = mix(
		reflection_texel(base, dimensions),
		reflection_texel(base + ivec2(1, 0), dimensions), blend.x
	);
	vec3 bottom = mix(
		reflection_texel(base + ivec2(0, 1), dimensions),
		reflection_texel(base + ivec2(1, 1), dimensions), blend.x
	);
	return mix(top, bottom, blend.y);
}

void fragment() {
	vec2 reflected = original_water_uv(vec2(UV.x, 1.0 - UV.y), TIME);
	vec3 accumulated = reflection_sample(reflected);
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			accumulated += reflection_sample(reflected + vec2(float(x), float(y)) * 0.0002);
		}
	}
	// The native program counts the center twice, yet divides by 25. It ignores
	// SpriteRenderer tint and does not add a depth gradient.
	vec3 result = accumulated * 0.04;
	COLOR = vec4(linear_framebuffer ? result : original_to_srgb(result), 1.0);
}
