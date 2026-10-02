shader_type canvas_item;
render_mode unshaded;

#include "res://Samples/ArtDirection/Shaders/OriginalColorSpace.gdshaderinc"
#include "res://Samples/ArtDirection/Shaders/OriginalChromatic.gdshaderinc"

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest, repeat_disable;
uniform float exposure_stops = 0.0;
uniform bool linear_framebuffer = false;
uniform sampler2D chromatic_source : hint_screen_texture, filter_linear, repeat_disable;
uniform float chromatic_amount = 0.0;

void fragment() {
	vec4 pixel = texture(screen_texture, SCREEN_UV);
	if (chromatic_amount > 0.0) {
		pixel.rgb = original_chromatic(chromatic_source, SCREEN_UV, chromatic_amount);
	}
	vec3 linear = linear_framebuffer ? pixel.rgb : original_to_linear(pixel.rgb);
	linear *= exp2(exposure_stops);
	COLOR = vec4(linear_framebuffer ? linear : original_to_srgb(linear), pixel.a);
}
