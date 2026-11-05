shader_type spatial;
// Enemy camouflage: three-colour blotches from the mesh's own (model-space)
// coordinates, so the pattern sticks to the vehicle or soldier. Flat colours,
// matching the low-poly look.

uniform vec3 color_a : source_color = vec3(0.31, 0.35, 0.20);
uniform vec3 color_b : source_color = vec3(0.42, 0.33, 0.19);
uniform vec3 color_c : source_color = vec3(0.13, 0.14, 0.10);
// Blotches per metre of model space (scale it for models not in metres).
uniform float pattern_scale = 0.9;
uniform float roughness_value = 0.85;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	vec3 p = local_pos * pattern_scale;
	float n = noise(p) * 0.65 + noise(p * 2.3 + 7.1) * 0.35;
	float m = noise(p * 1.4 + 31.0) * 0.7 + noise(p * 3.1 + 3.0) * 0.3;
	vec3 col = color_a;
	if (n > 0.55) {
		col = color_b;
	}
	if (m > 0.62) {
		col = color_c;
	}
	ALBEDO = col;
	ROUGHNESS = roughness_value;
}
