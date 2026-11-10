// Shared by ground_cover_canopy.gdshader (near: dithered) and ground_cover_canopy_far.gdshader
// (opaque). The mesh (geodata markvegetation.lager_glb) lies on the ground with the class index in
// UV.x; height and colour per class come from data/world/ground_cover.tres (GroundCoverCanopy).
uniform float class_height[16];
uniform vec3 class_color[16];

varying vec3 world_pos;
varying vec3 canopy_color;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x),
			mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	int ci = clamp(int(UV.x + 0.5), 0, 15);
	VERTEX.y += class_height[ci];
	canopy_color = class_color[ci];
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

vec3 canopy_albedo() {
	// patchy, like a field seen from afar (two octaves of value noise in world space)
	float n = noise2(world_pos.xz * 0.045) * 0.65 + noise2(world_pos.xz * 0.21) * 0.35;
	return canopy_color * (0.78 + 0.4 * n);
}
