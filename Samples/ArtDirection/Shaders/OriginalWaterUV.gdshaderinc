// Shader_Water2's shipped D3D11 pixel program (8), parameter layout (6).
// Inputs use Unity's Y-up sprite UVs; the Godot texture lookup flips Y separately.
uniform sampler2D water_normal : repeat_enable, filter_linear_mipmap;
uniform float water_speed;
uniform float water_strength;
uniform float water_tiling;
uniform float water_surface_speed;
uniform float water_camera_x;
uniform float water_time = -1.0;

float water_voronoi(vec2 coordinate, float angle) {
	vec2 cell = floor(coordinate);
	vec2 fraction = fract(coordinate);
	float nearest = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			uvec2 integer_cell = uvec2(ivec2(cell + offset));
			uint seed = integer_cell.y ^ 0x41c64e6du;
			uint mixed = (integer_cell.x + seed) * seed;
			mixed ^= mixed >> 5u;
			uint product = mixed * 0x27d4eb2du;
			uvec2 hash_value = uvec2(seed ^ (product << 3u), product) >> 8u;
			// Exact float32 constant from the bytecode: 1 / (2^24 - 1).
			vec2 phase = (vec2(hash_value) * angle) * 0.00000005960465188081798;
			vec2 random_point = vec2(sin(phase.x), cos(phase.y)) * 0.5;
			nearest = min(nearest, length(offset + random_point - fraction + vec2(0.5)));
		}
	}
	return nearest;
}

vec2 original_water_uv(vec2 uv, float clock) {
	float time = water_time < 0.0 ? clock : water_time;
	float scroll = time * water_speed + water_camera_x * 0.01;
	vec2 noise_uv = uv * water_tiling + vec2(scroll);
	vec2 dimensions = vec2(textureSize(water_normal, 0));
	vec2 dx = dFdx(noise_uv) * dimensions;
	vec2 dy = dFdy(noise_uv) * dimensions;
	float lod = max(0.0, floor(log2(max(length(dx), length(dy))) + 0.5));
	// Unity FilterMode.Bilinear selects one native mip, then filters its texels.
	vec4 packed_normal = textureLod(
		water_normal, vec2(noise_uv.x, 1.0 - noise_uv.y), lod
	);
	vec2 normal = vec2(packed_normal.r * packed_normal.a, packed_normal.g) * 2.0 - 1.0;
	vec2 reflected = vec2(uv.x, 1.0 - uv.y) + normal * water_strength;
	float first = water_voronoi(
		vec2(uv.x * 0.5 + scroll, uv.y * 5.0 + 0.5) * 50.0,
		time * water_surface_speed + 123.0
	);
	float second = water_voronoi(
		(uv * vec2(1.0, 34.959999084472656) + vec2(0.0, 1.0299999713897705)) * 10.0,
		time
	);
	float edge = clamp((uv.y - 1.0010000467300415) * -48.559669494628906, 0.0, 1.0);
	edge = edge * edge * (3.0 - 2.0 * edge);
	return reflected + vec2((first * second - 0.5) * 0.01 * edge);
}
