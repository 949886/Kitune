shader_type canvas_item;
render_mode unshaded;

#include "res://Samples/ArtDirection/Shaders/OriginalColorSpace.gdshaderinc"

uniform bool linear_framebuffer = false;
uniform vec4 line_color : source_color = vec4(1.0);
uniform vec4 gradient_color : source_color = vec4(1.0);
uniform float dash_length;
uniform float gap_length;
uniform float pixels_per_unit = 16.0;
uniform float endpoint_depth = 0.0;
varying vec3 world_position;

void vertex() {
	world_position = vec3((MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy, UV.x * endpoint_depth) / pixels_per_unit;
}

void fragment() {
	// Native Custom/LineRender/DottedLine program 3 estimates distance from
	// screen derivatives. Keep its dominant-axis choice, including diagonals.
	float du_dx = abs(dFdx(UV.x)) + 0.0000001;
	float du_dy = abs(dFdy(UV.x)) + 0.0000001;
	float length_x = length(dFdx(world_position)) / du_dx;
	float length_y = length(dFdy(world_position)) / du_dy;
	float distance_along = (du_dx >= du_dy ? length_x : length_y) * UV.x;
	float period = dash_length + gap_length;
	float ratio = dash_length / period;
	float phase = fract(distance_along / period);
	vec4 pixel = texture(TEXTURE, vec2(phase / ratio, UV.y));
	vec3 tint = line_color.rgb * gradient_color.rgb;
	if (!linear_framebuffer) {
		pixel.rgb = original_to_linear(pixel.rgb);
		tint = original_to_linear(line_color.rgb) * original_to_linear(gradient_color.rgb);
	}
	pixel.rgb *= tint;
	pixel.a *= line_color.a * gradient_color.a * step(phase, ratio);
	COLOR = vec4(linear_framebuffer ? pixel.rgb : original_to_srgb(pixel.rgb), pixel.a);
}
