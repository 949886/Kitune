shader_type canvas_item;
render_mode unshaded;

#include "res://Samples/ArtDirection/Shaders/OriginalColorSpace.gdshaderinc"
#include "res://Samples/ArtDirection/Shaders/OriginalEmission.gdshaderinc"
#include "res://Samples/ArtDirection/Shaders/OriginalParticleSampling.gdshaderinc"
#include "res://Samples/ArtDirection/Shaders/OriginalColorChange.gdshaderinc"
#include "res://Samples/ArtDirection/Shaders/OriginalBaseOutline.gdshaderinc"
#include "res://Samples/ArtDirection/Shaders/OriginalInnerOutline.gdshaderinc"
#include "res://Samples/ArtDirection/Shaders/OriginalUV.gdshaderinc"
#include "res://Samples/ArtDirection/Shaders/OriginalPerspective.gdshaderinc"

varying vec4 tint;

void vertex() {
	// Keep the original renderer tint separate from fragment-stage texture sampling.
	tint = COLOR;
	perspective_uv = original_projective_uv(UV, VERTEX);
}

void fragment() {
	vec2 source_uv = perspective_uv.xy / perspective_uv.z;
	vec2 uv = original_effect_uv(source_uv, vec2(textureSize(TEXTURE, 0)), SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, TIME);
	vec4 pixel = original_particle_sample(TEXTURE, uv, tint);
	pixel = original_color_change(pixel);
	pixel = original_inner_outline(TEXTURE, uv, pixel);
	pixel = original_outlined_surface(TEXTURE, uv, pixel, tint.a);
	pixel.a *= original_source_clip(source_uv);
	COLOR = vec4(linear_framebuffer ? pixel.rgb : original_to_srgb(pixel.rgb), pixel.a);
}
