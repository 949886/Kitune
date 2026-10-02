// Canvas vertices have already been projected on the CPU so Godot culls their
// actual screen bounds. Interpolate UV / W and 1 / W, then divide per fragment.
// The identity row preserves the existing parallel-sprite path exactly.
uniform vec3 perspective_weight_row = vec3(0.0, 0.0, 1.0);
varying vec3 perspective_uv;

vec3 original_projective_uv(vec2 uv, vec2 vertex) {
	float weight = dot(perspective_weight_row, vec3(vertex, 1.0));
	return vec3(uv * weight, weight);
}
