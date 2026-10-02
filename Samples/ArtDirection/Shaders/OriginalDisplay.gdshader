shader_type canvas_item;
render_mode unshaded;

#include "res://Samples/ArtDirection/Shaders/OriginalColorSpace.gdshaderinc"

void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	COLOR = vec4(original_to_srgb(pixel.rgb), pixel.a);
}
