shader_type canvas_item;
render_mode unshaded;
#include "../../Core/Native/Shaders/OriginalColorSpace.gdshaderinc"
#include "../../Core/Native/Shaders/OriginalEmission.gdshaderinc"
#include "../../Core/Native/Shaders/OriginalParticleSampling.gdshaderinc"
#include "../../Core/Native/Shaders/OriginalColorChange.gdshaderinc"
#include "../../Core/Native/Shaders/OriginalBaseOutline.gdshaderinc"
#include "../../Core/Native/Shaders/OriginalInnerOutline.gdshaderinc"
#include "../../Core/Native/Shaders/OriginalUV.gdshaderinc"
#include "../../Core/Native/Shaders/OriginalPerspective.gdshaderinc"
uniform sampler2D mask_texture : filter_nearest, repeat_disable;
uniform vec3 mask_x;
uniform vec3 mask_y;
uniform float mask_cutoff = 0.2;
uniform bool mask_enabled = false;
varying vec2 mask_uv;
varying vec4 tint;
void vertex() {
	tint = COLOR;
	perspective_uv = original_projective_uv(UV, VERTEX);
	mask_uv = vec2(dot(mask_x, vec3(VERTEX, 1.0)), dot(mask_y, vec3(VERTEX, 1.0)));
}
void fragment() {
	// Source renderers use VisibleOutsideMask within a local SortingGroup.
	if (mask_enabled && all(greaterThanEqual(mask_uv, vec2(0.0))) && all(lessThanEqual(mask_uv, vec2(1.0))) && texture(mask_texture, mask_uv).a > mask_cutoff) { discard; }
	vec2 source_uv = perspective_uv.xy / perspective_uv.z;
	vec2 uv = original_effect_uv(source_uv, vec2(textureSize(TEXTURE, 0)), SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, TIME);
	vec4 pixel = original_particle_sample(TEXTURE, uv, tint);
	pixel = original_color_change(pixel);
	pixel = original_inner_outline(TEXTURE, uv, pixel);
	pixel = original_outlined_surface(TEXTURE, uv, pixel, tint.a);
	pixel.a *= original_source_clip(source_uv);
	COLOR = vec4(linear_framebuffer ? pixel.rgb : original_to_srgb(pixel.rgb), pixel.a);
}
