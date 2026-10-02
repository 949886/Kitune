shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D scene_texture : hint_screen_texture, filter_linear, repeat_disable;
uniform float distortion_strength;
uniform float distortion_range;
uniform float distortion_scale;
uniform float distortion_softness;
uniform float twirl_strength;
uniform vec2 flow_speed;

// Recovered D3D11 gradient hash from the shipped SquareDistortion fragment
// program. The right shift is unsigned and the float divisor is 2^24 - 1.
vec2 gradient(vec2 cell) {
	uint y = uint(int(cell.y)) ^ uint(0x41c64e6d);
	uint hash = (uint(int(cell.x)) + y) * y;
	hash = (hash ^ (hash >> uint(5))) * uint(0x27d4eb2d);
	float value = float(hash >> uint(8)) / 16777215.0;
	return normalize(vec2(value - floor(value + 0.5), value - 0.5));
}

float gradient_noise(vec2 uv) {
	vec2 cell = floor(uv);
	vec2 point = fract(uv);
	vec2 blend = point * point * point * (point * (point * 6.0 - 15.0) + 10.0);
	float a = dot(gradient(cell), point);
	float b = dot(gradient(cell + vec2(0, 1)), point - vec2(0, 1));
	float c = dot(gradient(cell + vec2(1, 0)), point - vec2(1, 0));
	float d = dot(gradient(cell + vec2(1, 1)), point - vec2(1, 1));
	return mix(mix(a, b, blend.y), mix(c, d, blend.y), blend.x);
}

void fragment() {
	// Mesh UVs are the original Unity UVs (Y up), not cropped Sprite2D UVs.
	vec2 centered = UV - vec2(0.5);
	float angle = length(centered) * twirl_strength;
	vec2 twisted = vec2(cos(angle) * centered.x - sin(angle) * centered.y,
		sin(angle) * centered.x + cos(angle) * centered.y);
	vec2 sample_uv = (twisted + flow_speed * TIME + vec2(0.5)) * distortion_scale;
	float noise = gradient_noise(sample_uv) * distortion_strength * 0.1;
	// Do not replace reversed-edge smoothstep with GLSL smoothstep: its result
	// is undefined there. The source uses this explicit saturate polynomial.
	vec2 a = clamp((centered - vec2(distortion_range)) / (distortion_softness - distortion_range), vec2(0), vec2(1));
	vec2 b = clamp((centered + vec2(distortion_range)) / (distortion_softness + distortion_range), vec2(0), vec2(1));
	a = a * a * (3.0 - 2.0 * a);
	b = b * b * (3.0 - 2.0 * b);
	float offset = noise * a.x * a.y * b.x * b.y;
	COLOR = vec4(texture(scene_texture, SCREEN_UV + vec2(offset, -offset)).rgb, 1.0);
}
