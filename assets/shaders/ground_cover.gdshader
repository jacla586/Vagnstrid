shader_type spatial;
// Ground vegetation near the camera (GroundCoverField): blade clumps from a MultiMesh.
// COLOR: rgb = the clump's tip colour (MultiMesh instance colour), a = height along the blade
// (0 base .. 1 tip). Blades sway with the wind; beyond fade_start..fade_end they would shrink into
// the ground (off by default: GroundCoverCanopy takes over under the outer blades).
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform float sway_m = 0.06;
uniform vec2 wind_dir = vec2(1.0, 0.4);
uniform float fade_start = 1.0e6;
uniform float fade_end = 2.0e6;
uniform float base_darkness = 0.45;

varying float tip;

void vertex() {
	tip = COLOR.a;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * 1.6 + dot(world.xz, vec2(0.21, 0.13));
	float gust = sin(t) * 0.7 + sin(t * 2.3 + 1.7) * 0.3;
	vec3 sway = vec3(wind_dir.x, 0.0, wind_dir.y) * gust * sway_m * tip * tip;
	world += sway;
	float d = length(world - CAMERA_POSITION_WORLD);
	float keep = 1.0 - smoothstep(fade_start, fade_end, d);
	vec3 root = (MODEL_MATRIX * vec4(VERTEX.x, 0.0, VERTEX.z, 1.0)).xyz;
	world.y = mix(root.y, world.y, keep);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

void fragment() {
	ALBEDO = COLOR.rgb * mix(base_darkness, 1.0, tip);
	ROUGHNESS = 0.95;
	BACKLIGHT = vec3(0.15, 0.2, 0.05) * tip;
}
