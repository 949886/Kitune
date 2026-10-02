shader_type canvas_item;
render_mode unshaded;

#include "OriginalColorSpace.gdshaderinc"

// URP 2022.3 Particles.hlsl / ParticlesUnlitInput.hlsl, Unity Graphics (MIT).
// The source arrow materials use straight alpha and Color or Add/Subtract modes.
uniform bool linear_framebuffer = false;
uniform vec4 material_tint : source_color = vec4(1.0);
uniform int color_mode = 0;
uniform vec2 color_operation = vec2(0.0);
varying vec4 particle_tint;

vec3 rgb_to_hsv(vec3 rgb) {
	float highest = max(rgb.r, max(rgb.g, rgb.b));
	float lowest = min(rgb.r, min(rgb.g, rgb.b));
	float span = highest - lowest;
	float hue = 0.0;
	if (span > 0.000001) {
		if (highest == rgb.r) {
			hue = (rgb.g - rgb.b) / span;
		} else if (highest == rgb.g) {
			hue = 2.0 + (rgb.b - rgb.r) / span;
		} else {
			hue = 4.0 + (rgb.r - rgb.g) / span;
		}
	}
	return vec3(fract(hue / 6.0 + 1.0), highest > 0.0 ? span / highest : 0.0, highest);
}

vec3 hsv_to_rgb(vec3 hsv) {
	vec3 ramp = abs(fract(hsv.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return hsv.z * mix(vec3(1.0), clamp(ramp - 1.0, vec3(0.0), vec3(1.0)), hsv.y);
}

void vertex() {
	particle_tint = COLOR;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec4 tint = particle_tint;
	vec4 constant_tint = material_tint;
	if (!linear_framebuffer) {
		base.rgb = original_to_linear(base.rgb);
		tint.rgb = original_to_linear(tint.rgb);
		constant_tint.rgb = original_to_linear(constant_tint.rgb);
	}
	base *= constant_tint;
	vec3 surface = base.rgb * tint.rgb;
	if (color_mode == 1) {
		vec3 hsv = rgb_to_hsv(tint.rgb);
		surface = hsv_to_rgb(vec3(hsv.xy, rgb_to_hsv(base.rgb).z));
	} else if (color_mode == 2) {
		surface = base.rgb + tint.rgb * color_operation.x;
		surface = mix(surface, abs(surface), color_operation.y);
	}
	COLOR = vec4(linear_framebuffer ? surface : original_to_srgb(surface), base.a * tint.a);
}
