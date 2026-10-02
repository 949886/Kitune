shader_type canvas_item;
render_mode unshaded, blend_disabled;

#include "res://Samples/ArtDirection/Shaders/OriginalColorSpace.gdshaderinc"
#include "res://Samples/ArtDirection/Shaders/OriginalChromatic.gdshaderinc"

uniform sampler2D bloom_texture : filter_linear, repeat_disable;
uniform float intensity = 0.2;
uniform vec3 bloom_tint = vec3(1.0);
uniform float exposure_stops = 0.0;
uniform bool linear_destination = false;
uniform float letterbox = 0.0;
uniform sampler2D chromatic_source : filter_linear, repeat_disable;
uniform float chromatic_amount = 0.0;

void fragment() {
	vec3 color = texture(TEXTURE, UV).rgb;
	if (chromatic_amount > 0.0) {
		color = original_chromatic(chromatic_source, UV, chromatic_amount);
	}
	color += texture(bloom_texture, UV).rgb * intensity * bloom_tint;
	color *= exp2(exposure_stops);
	color = linear_destination ? color : original_to_srgb(color);
	// Source cinematic bars overlay the completed image; they do not bloom.
	if (UV.y < letterbox || UV.y > 1.0 - letterbox) {
		color = vec3(0.0);
	}
	COLOR = vec4(color, 1.0);
}
