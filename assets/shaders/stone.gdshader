shader_type spatial;
// Boulders from the geodata glb (group Stenar; StoneLook puts this on them). The meshes are
// low-poly blobs with shared (smooth) normals, which drew as flat grey patches: here every face
// is shaded on its own (normal from the screen-space derivatives of the position), so the facets
// catch the light, and the colour comes from world-space noise: grain, mottled patches, pale
// lichen, moss on the faces that look up and darker undersides. Cosmetic only.
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 rock_color : source_color = vec3(0.64, 0.60, 0.53);
uniform vec3 rock_dark : source_color = vec3(0.36, 0.34, 0.31);
uniform vec3 rock_warm : source_color = vec3(0.68, 0.58, 0.48);
uniform vec3 lichen_color : source_color = vec3(0.78, 0.78, 0.66);
uniform vec3 moss_color : source_color = vec3(0.40, 0.46, 0.20);
// Share of the upward faces covered by moss (0..1), and how far the lichen spreads.
uniform float moss_amount = 0.85;
uniform float lichen_amount = 0.42;
uniform float wetness = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return noise3(p) * 0.5 + noise3(p * 2.03) * 0.3 + noise3(p * 4.1) * 0.2;
}

void fragment() {
	// One flat normal per face (view space), so the facets show.
	vec3 n = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	NORMAL = n;
	vec3 wn = (INV_VIEW_MATRIX * vec4(n, 0.0)).xyz;

	// Mottled rock: big patches, warm and dark, plus a fine grain.
	float big = fbm(world_pos * 0.7);
	float grain = noise3(world_pos * 9.0);
	vec3 col = mix(rock_dark, rock_color, smoothstep(0.25, 0.7, big));
	col = mix(col, rock_warm, smoothstep(0.45, 0.8, fbm(world_pos * 0.35 + 7.3)) * 0.7);
	col *= 0.75 + 0.5 * grain;
	// Each face a touch lighter or darker than its neighbours (breaks the surface up more).
	col *= 0.9 + 0.2 * hash3(floor(wn * 6.0) + floor(world_pos * 0.5));

	// Pale lichen blotches, mostly on the sides and top.
	float lichen = smoothstep(1.0 - lichen_amount, 1.0 - lichen_amount + 0.06, fbm(world_pos * 0.9 + 3.1));
	col = mix(col, lichen_color * (0.85 + 0.3 * grain), lichen * smoothstep(-0.3, 0.3, wn.y) * 0.8);
	// Moss where the faces look up, ragged at its edge.
	float up = smoothstep(0.5, 0.9, wn.y + (fbm(world_pos * 1.1) - 0.5) * 0.7);
	col = mix(col, moss_color * (0.8 + 0.4 * grain), up * moss_amount);
	// Undersides in shade and dirt.
	col *= mix(0.6, 1.0, smoothstep(-0.6, 0.1, wn.y));

	ALBEDO = col * mix(1.0, 0.6, wetness);
	ROUGHNESS = mix(mix(0.88, 0.97, up * moss_amount), 0.35, wetness);
	SPECULAR = 0.3;
}
