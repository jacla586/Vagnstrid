shader_type spatial;
// Enemy camouflage after the Swedish M90: angular splinter fields in light green, mid
// green, dark green and black, all leaning the same way. Built from the mesh's own
// (model-space) coordinates, so the pattern sticks to the vehicle or soldier; each face
// is projected along its main axis. Flat colours to match the low-poly look.
//
// The fields are Voronoi cells in a rotated, stretched space (so their straight edges
// lean together and they come out as long shards, not little spiky triangles), and a
// second, finer layer adds the black splinters. Borders are blended over one pixel
// (fwidth), so edges stay clean instead of stair-stepped at a distance.

uniform vec3 color_base : source_color = vec3(0.56, 0.60, 0.42);  // light green
uniform vec3 color_a : source_color = vec3(0.33, 0.42, 0.25);     // mid green
uniform vec3 color_b : source_color = vec3(0.17, 0.25, 0.15);     // dark green
uniform vec3 color_c : source_color = vec3(0.08, 0.09, 0.07);     // black
// Fields per metre of model space (scale it for models not in metres).
uniform float pattern_scale = 0.75;
// Share of the fields in mid and dark green (the rest is light green), and of the fine
// layer's cells that are black.
uniform float cover_a = 0.36;
uniform float cover_b = 0.30;
uniform float cover_c = 0.22;
// How long the shards are for their width, and which way they lean (radians).
uniform float stretch = 2.6;
uniform float lean = 0.5;
uniform float roughness_value = 0.85;

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

vec2 hash2(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.xx + q.yz) * q.zy);
}

float hash1(vec2 p) {
	return hash2(p + 71.3).x;
}

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Voronoi in the leaning, stretched space: the nearest cell's id, the second nearest's,
// and the distance to the border between them (in that space).
void voronoi(vec2 p, float angle, out vec2 id1, out vec2 id2, out float border) {
	vec2 q = rot(p, angle);
	q.x /= stretch;
	vec2 cell = floor(q);
	vec2 f = fract(q);
	float d1 = 1e9;
	float d2 = 1e9;
	vec2 p1 = vec2(0.0);
	vec2 p2 = vec2(0.0);
	id1 = cell;
	id2 = cell;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = g + 0.15 + 0.7 * hash2(cell + g);
			vec2 r = o - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1; p2 = p1; id2 = id1;
				d1 = d; p1 = o; id1 = cell + g;
			} else if (d < d2) {
				d2 = d; p2 = o; id2 = cell + g;
			}
		}
	}
	// Distance from f to the bisector of the two nearest points.
	border = dot(f - (p1 + p2) * 0.5, normalize(p1 - p2));
}

vec3 field_colour(vec2 id) {
	float h = hash1(id);
	if (h < cover_b) {
		return color_b;
	} else if (h < cover_b + cover_a) {
		return color_a;
	}
	return color_base;
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
	// Green fields.
	vec2 id1;
	vec2 id2;
	float border;
	voronoi(uv, lean, id1, id2, border);
	float w = max(fwidth(border), 1e-4);
	vec3 col = mix(field_colour(id2), field_colour(id1), 0.5 + 0.5 * smoothstep(0.0, w, border));
	// Black splinters: a finer, slightly turned layer; only some of its cells are black.
	vec2 jd1;
	vec2 jd2;
	float jb;
	voronoi(uv * 1.7 + vec2(13.1, 7.7), lean + 0.25, jd1, jd2, jb);
	float wj = max(fwidth(jb), 1e-4);
	float black1 = hash1(jd1 + 101.0) < cover_c ? 1.0 : 0.0;
	float black2 = hash1(jd2 + 101.0) < cover_c ? 1.0 : 0.0;
	float black = mix(black2, black1, 0.5 + 0.5 * smoothstep(0.0, wj, jb));
	col = mix(col, color_c, black);
	ALBEDO = col;
	ROUGHNESS = roughness_value;
}
