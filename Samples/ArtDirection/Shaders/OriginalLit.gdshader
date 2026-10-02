shader_type canvas_item;
render_mode unshaded;

#include "res://Samples/ArtDirection/Shaders/OriginalColorSpace.gdshaderinc"
#include "res://Samples/ArtDirection/Shaders/OriginalEmission.gdshaderinc"
#include "res://Samples/ArtDirection/Shaders/OriginalParticleSampling.gdshaderinc"
#include "res://Samples/ArtDirection/Shaders/OriginalBaseOutline.gdshaderinc"
#include "res://Samples/ArtDirection/Shaders/OriginalInnerOutline.gdshaderinc"
#include "res://Samples/ArtDirection/Shaders/OriginalUV.gdshaderinc"
#include "res://Samples/ArtDirection/Shaders/OriginalPerspective.gdshaderinc"

uniform sampler2D light_data : filter_nearest, repeat_disable;
uniform sampler2D falloff_lookup : filter_linear, repeat_disable;
uniform int light_count = 0;
uniform vec3 ambient = vec3(1.0);
uniform bool glow_affects_light = false;
uniform vec3 lighting_mask = vec3(1.0);
uniform sampler2D lighting_mask_texture : filter_nearest, repeat_disable;
uniform bool lighting_mask_textured = false;
uniform bool lighting_mask_srgb = false;
uniform float lit_amount = 1.0;

varying vec4 renderer_tint;
varying vec2 world_position;

void vertex() {
	renderer_tint = COLOR;
	perspective_uv = original_projective_uv(UV, VERTEX);
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 source_uv = perspective_uv.xy / perspective_uv.z;
	vec2 uv = original_effect_uv(source_uv, vec2(textureSize(TEXTURE, 0)), SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, TIME);
	vec4 pixel = original_particle_sample(TEXTURE, uv, renderer_tint);
	pixel = original_inner_outline(TEXTURE, uv, pixel);
	pixel = original_outlined_surface(TEXTURE, uv, pixel, renderer_tint.a);
	vec3 illumination = ambient;

	for (int i = 0; i < light_count; i++) {
		vec4 bounds = texelFetch(light_data, ivec2(0, i), 0);
		vec2 delta = world_position - bounds.xy;
		float distance_to_light = length(delta);
		if (distance_to_light >= bounds.z) {
			continue;
		}

		vec4 radiance = texelFetch(light_data, ivec2(1, i), 0);
		vec4 cone = texelFetch(light_data, ivec2(2, i), 0);
		vec4 normal = texelFetch(light_data, ivec2(3, i), 0);
		float radial_range = max(bounds.z - bounds.w, 0.0001);
		float radial = clamp((bounds.z - distance_to_light) / radial_range, 0.0, 1.0);

		// URP's lookup measures angle from local down, with Y reversed for Godot.
		float local_y = dot(delta, vec2(-cone.y, cone.x));
		float angle_cosine = clamp(local_y / max(distance_to_light, 0.0001), -1.0, 1.0);
		float angle_lookup = 1.0 - acos(angle_cosine) / PI;
		float spot = 1.0;
		if (cone.z < 1.0) {
			spot = clamp((cone.w - angle_lookup) / max(cone.w - cone.z, 0.0001), 0.0, 1.0);
		}

		// The PNG is exported top-down; Unity's lookup V axis starts at the bottom.
		vec2 falloff_uv = vec2(radial * spot, 1.0 - radiance.a);
		float attenuation = texture(falloff_lookup, falloff_uv).r;
		if (normal.y < 1.5) {
			// Flat sprite normal. Imported normal textures are not reconstructed yet.
			float direction_length = length(vec2(distance_to_light, normal.x));
			attenuation *= normal.x / max(direction_length, 0.0001);
		}

		if (normal.z > 0.5) {
			illumination = mix(illumination, radiance.rgb, attenuation);
		} else {
			illumination += radiance.rgb * attenuation;
		}
	}

	vec3 linear = pixel.rgb * illumination;
	if (glow_affects_light) {
		// GLOWLIGHT_ON retains bright surface emission as lighting is reduced.
		vec3 mask = lighting_mask;
		if (lighting_mask_textured) {
			// The source GLOWLIGHT pixel program samples _MaskTex with the same
			// atlas UV as _MainTex. Decode this raw sampler once on every renderer.
			mask = texture(lighting_mask_texture, uv).rgb;
			if (lighting_mask_srgb) {
				mask = original_to_linear(mask);
			}
		}
		mask = clamp(mask * lit_amount, vec3(0.0), vec3(1.0));
		vec3 weight = clamp(2.0 * mask - pixel.rgb, vec3(0.0), vec3(1.0));
		linear = mix(pixel.rgb, linear, weight);
	}
	pixel.a *= original_source_clip(source_uv);
	COLOR = vec4(linear_framebuffer ? linear : original_to_srgb(linear), pixel.a);
}
