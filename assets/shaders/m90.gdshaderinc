// M90-like splinter camouflage, shared by camo.gdshader (soldiers) and
// tank_paint.gdshader (enemy tanks). Leaning, stretched Voronoi fields in light, mid and
// dark green, a finer layer of black splinters, borders blended over a pixel (fwidth).
// The including shader declares: color_base, color_a, color_b, color_c, cover_a,
// cover_b, cover_c, stretch, lean.

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

// The camouflage colour at `uv` (face-projected model-space position × pattern scale).
vec3 m90_colour(vec2 uv) {
	vec2 id1;
	vec2 id2;
	float border;
	voronoi(uv, lean, id1, id2, border);
	float w = max(fwidth(border), 1e-4);
	vec3 col = mix(field_colour(id2), field_colour(id1), 0.5 + 0.5 * smoothstep(0.0, w, border));
	vec2 jd1;
	vec2 jd2;
	float jb;
	voronoi(uv * 1.7 + vec2(13.1, 7.7), lean + 0.25, jd1, jd2, jb);
	float wj = max(fwidth(jb), 1e-4);
	float black1 = hash1(jd1 + 101.0) < cover_c ? 1.0 : 0.0;
	float black2 = hash1(jd2 + 101.0) < cover_c ? 1.0 : 0.0;
	float black = mix(black2, black1, 0.5 + 0.5 * smoothstep(0.0, wj, jb));
	return mix(col, color_c, black);
}

// Face projection of a model-space point: along the face's main axis.
vec2 face_uv(vec3 p, vec3 n) {
	vec3 an = abs(n);
	if (an.y > an.x && an.y > an.z) {
		return p.xz;
	} else if (an.x > an.z) {
		return p.zy;
	}
	return p.xy;
}
