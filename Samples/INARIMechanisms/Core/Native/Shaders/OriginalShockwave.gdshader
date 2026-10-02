shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D sorting_layer_texture : hint_screen_texture, filter_linear, repeat_disable;
uniform float age_percent = 0.0;
uniform float distortion_strength = 0.0;
uniform float ring_size = 0.2;

void fragment() {
	// Native TEXCOORD0.z is ParticleSystemVertexStream.AgePercent. Neither
	// particle color nor _MainTex participates in this shader's pixel program.
	vec2 radial = vec2(UV.x, 1.0 - UV.y) * 2.0 - 1.0;
	float radius = length(radial);
	float age = fract(age_percent);
	float transition = smoothstep(age - ring_size, age + ring_size, radius);
	float strength = clamp((1.0 - radius) * transition * (1.0 - transition) * distortion_strength, 0.0, 1.0);
	vec2 offset = radius > 0.0 ? radial / radius * strength * (1.0 - age_percent) : vec2(0.0);
	// Unity's UV Y points up; Godot's scene snapshot Y points down.
	vec2 sample_uv = SCREEN_UV + vec2(offset.x, -offset.y);
	COLOR = vec4(texture(sorting_layer_texture, sample_uv).rgb, 1.0);
}
