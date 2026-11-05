shader_type spatial;
// Enemy camouflage: a splinter pattern after the Swedish M90 (sharp-edged, angular
// shards in light green, mid green, dark green and black, leaning the same few
// ways). Built from the mesh's own (model-space) coordinates, so the pattern sticks to
// the vehicle or soldier; each face is projected along its main axis. Flat colours,
// matching the low-poly look.

uniform vec3 color_base : source_color = vec3(0.56, 0.60, 0.42);  // light green
uniform vec3 color_a : source_color = vec3(0.33, 0.42, 0.25);     // mid green
uniform vec3 color_b : source_color = vec3(0.17, 0.25, 0.15);     // dark green
uniform vec3 color_c : source_color = vec3(0.08, 0.09, 0.07);     // black
// Shards per metre of model space (scale it for models not in metres).
uniform float pattern_scale = 0.9;
// Share of the surface each layer covers (black is the smallest).
uniform float cover_a = 0.55;
uniform float cover_b = 0.45;
uniform float cover_c = 0.22;
uniform float roughness_value = 0.85;

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// One layer of shards: a stretched, tilted grid; each cell keeps the part on one side
// of a random straight cut (so its shard is a triangle or a quadrilateral), and only
// some cells have one. Neighbouring shards join into longer angular strips.
float shards(vec2 p, float angle, float stretch, float cover, float seed) {
	vec2 q = rot(p, angle);
	q.x /= stretch;
	// shear every other row so cells don't line up
	q.x += floor(q.y) * 0.37;
	vec2 cell = floor(q);
	vec2 f = fract(q) - 0.5;
	if (hash(cell + seed) > cover) {
		return 0.0;
	}
	float a = hash(cell + seed + 17.0) * 3.14159;
	vec2 n = vec2(cos(a), sin(a));
	float offset = (hash(cell + seed + 41.0) - 0.5) * 0.5;
	return dot(f, n) > offset ? 1.0 : 0.0;
}

float layer(vec2 p, float cover, float seed) {
	// Two crossing directions per colour, like M90's leaning splinters.
	float s1 = shards(p, 0.55 + seed * 0.01, 2.6, cover, seed);
	float s2 = shards(p * 1.3 + 5.0, -0.35 + seed * 0.01, 2.2, cover * 0.7, seed + 7.0);
	return max(s1, s2);
}

void fragment() {
	vec3 an = abs(local_normal);
	vec3 p = local_pos * pattern_scale;
	vec2 uv;
	if (an.y > an.x && an.y > an.z) {
		uv = p.xz;
	} else if (an.x > an.z) {
		uv = p.zy;
	} else {
		uv = p.xy;
	}
	vec3 col = color_base;
	if (layer(uv, cover_a, 1.0) > 0.5) {
		col = color_a;
	}
	if (layer(uv * 1.15 + 11.0, cover_b, 23.0) > 0.5) {
		col = color_b;
	}
	if (layer(uv * 1.4 + 29.0, cover_c, 51.0) > 0.5) {
		col = color_c;
	}
	ALBEDO = col;
	ROUGHNESS = roughness_value;
}
