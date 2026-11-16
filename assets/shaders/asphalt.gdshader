shader_type spatial;
// Asphalt and road paint (RoadLook puts it on the geodata glb's road meshes).
// World-space wear: tone patches, aggregate grain, cracks, repairs (darker blobs with a seam), oil down
// the lane centres and wheel ruts. Ruts need the road position the geodata pipeline writes into UV
// (vagyta.lage_uv; glTF export flips v): UV.x = metres left of the centre line, 1 - UV.y = half width
// (+ 50 on one-way carriageways, < 0 = no position: junction fillets, bays). Wet: darker, glossy,
// puddles in the ruts. paint = 1: road markings, worn towards the asphalt by the same wear.

uniform vec3 base_color : source_color = vec3(0.24, 0.24, 0.25);
uniform float wear : hint_range(0.0, 1.0) = 0.5;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float paint : hint_range(0.0, 1.0) = 0.0;
uniform vec3 paint_under : source_color = vec3(0.24, 0.24, 0.25);

varying vec3 wpos;

float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
	float n = hash2(p);
	return vec2(n, hash2(p + n + 17.0));
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x),
			mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(13.1, 7.7);
		a *= 0.5;
	}
	return s;
}

// distance to the nearest Voronoi cell border (cracks)
float voronoi_edge(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 best_g = vec2(0.0);
	vec2 best_r = vec2(8.0);
	float d1 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 r = g + hash22(i + g) - f;
			float d = dot(r, r);
			if (d < d1) {
				d1 = d;
				best_r = r;
				best_g = g;
			}
		}
	}
	float e = 8.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			vec2 g = best_g + vec2(float(x), float(y));
			vec2 r = g + hash22(i + g) - f;
			if (dot(r - best_r, r - best_r) > 0.00001) {
				e = min(e, dot(0.5 * (best_r + r), normalize(r - best_r)));
			}
		}
	}
	return e;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float px = max(fwidth(p.x), fwidth(p.y));          // metres per pixel: fine detail fades out far away
	float near_fine = 1.0 - smoothstep(0.01, 0.05, px);
	float near_mid = 1.0 - smoothstep(0.05, 0.4, px);

	// tone: large soft patches and finer mottling
	float tone = (fbm(p * 0.07) - 0.5) * 0.16 + (fbm(p * 0.6) - 0.5) * 0.10 * near_mid;
	// aggregate: light stones in the binder, more exposed when worn
	float grain = hash2(floor(p * 40.0));
	float stones = step(0.86 - wear * 0.1, grain) * 0.10 * near_fine;
	float speck = (grain - 0.5) * 0.06 * near_fine;

	// repairs: irregular darker (newer) blobs with a dark seam, more on worn roads
	float rep_n = fbm(p * 0.35 + vec2(41.0, 9.0));
	float rep_lim = 0.79 - wear * 0.08;
	float repair = smoothstep(rep_lim, rep_lim + 0.004, rep_n);
	float seam = (1.0 - smoothstep(0.0, 0.012, abs(rep_n - rep_lim))) * near_mid;

	// cracks: cell borders ~2.5 m, only where a slow mask says the surface is cracked
	float crack_mask = smoothstep(0.55 - wear * 0.25, 0.75 - wear * 0.25, fbm(p * 0.05 + vec2(3.0, 71.0)));
	float crack = 0.0;
	if (near_mid > 0.0 && crack_mask > 0.0) {
		float wob = (vnoise(p * 3.0) - 0.5) * 0.12;
		float ce = voronoi_edge(p * 0.4 + wob);
		crack = (1.0 - smoothstep(0.0, 0.025 + px * 0.4, ce)) * crack_mask * (1.0 - repair) * near_mid;
	}

	// wheel ruts and oil from the road position
	float rut = 0.0;
	float oil = 0.0;
	float hw_raw = 1.0 - UV.y;
	if (hw_raw > 0.5) {
		bool oneway = hw_raw > 40.0;
		float hw = oneway ? hw_raw - 50.0 : hw_raw;
		float v = UV.x;
		float lane;
		if (oneway) {
			float n = max(1.0, floor(2.0 * hw / 3.3 + 0.5));
			float lw = 2.0 * hw / n;
			lane = (fract((v + hw) / lw) - 0.5) * lw;
		} else if (hw < 2.8) {
			lane = v;                         // narrow street: one shared lane
		} else {
			lane = abs(v) - hw * 0.5;
		}
		float d = abs(abs(lane) - 0.85);
		float along = fbm(p * 0.25 + vec2(5.0, 5.0));
		rut = exp(-d * d / 0.06) * (0.6 + 0.4 * along) * smoothstep(0.5, 1.5, hw);
		oil = exp(-lane * lane / 0.08) * smoothstep(0.45, 0.7, fbm(p * 0.5 + vec2(17.0, 3.0))) * near_mid;
	}

	vec3 col = base_color * (1.0 + tone + speck);
	col = mix(col, vec3(0.62, 0.61, 0.58), stones);
	col *= 1.0 - repair * 0.15;
	col *= 1.0 - seam * 0.2;
	col *= 1.0 - crack * 0.55;
	col *= 1.0 - rut * 0.10 * (0.5 + wear);
	col *= 1.0 - oil * 0.12;
	float rough = 0.86 - rut * 0.12 - repair * 0.04;

	if (paint > 0.5) {
		// worn paint: patches where the asphalt shows through, worse in the ruts
		float worn = smoothstep(0.35, 0.75, fbm(p * 1.3 + vec2(91.0, 12.0)) + rut * 0.35 + wear * 0.2 - 0.25);
		vec3 pc = base_color * (1.0 + speck * 0.5);
		col = mix(pc, paint_under * (1.0 + tone), worn * 0.75);
		rough = 0.7;
	}

	// wet: darker, glossy; standing water in ruts and dips
	float puddle = wetness * smoothstep(0.35, 0.55, rut * 0.6 + (fbm(p * 0.12 + vec2(55.0, 1.0)) - 0.45) * 1.4);
	col *= 1.0 - wetness * 0.35;
	rough = mix(rough, 0.25, wetness * 0.8);
	rough = mix(rough, 0.04, puddle);
	col *= 1.0 - puddle * 0.25;

	ALBEDO = clamp(col, 0.0, 1.0);
	ROUGHNESS = rough;
	SPECULAR = 0.5;
}
