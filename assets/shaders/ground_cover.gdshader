shader_type spatial;
// Ground vegetation (GroundCoverField): blade clumps from a MultiMesh.
// COLOR: rgb = the clump's tip colour (MultiMesh instance colour) × the blade's own tint,
// a = height along the blade (0 base .. 1 tip). INSTANCE_CUSTOM.r = the clump's rank (0..1).
// Distances are "seen" ones: true distance / zoom (the camera's FOV against ref_tan_half), so
// the gunner's sight and binoculars see grass as far out as it looks near. Beyond
// full_density_m only clumps of rank < (full / d)^thin_exponent are drawn, widened by
// 1 / sqrt of that (at most max_widen), so the ground stays about as covered; zoomed views
// thin by 1 / zoom^zoom_thin_exponent as well (they see more depth per pixel row); the last quarter of
// blade_range_m thins to nothing (GroundCoverCanopy takes over). A clump about to drop
// shrinks first, so nothing pops. Blades sway with the wind; lit with an upward normal like
// the ground under them, with a little light through the tips.
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform float sway_m = 0.06;
uniform vec2 wind_dir = vec2(1.0, 0.4);
uniform float ref_tan_half = 0.7;
uniform float full_density_m = 35.0;
uniform float blade_range_m = 160.0;
uniform float max_widen = 5.0;
uniform float thin_exponent = 3.0;
uniform float zoom_thin_exponent = 0.6;
uniform float flat_colour_m = 80.0;
uniform float base_darkness = 0.62;

varying float tip;
varying float far_flat;
varying vec3 world_pos;

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
	tip = COLOR.a;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float zoom = ref_tan_half * abs(PROJECTION_MATRIX[1][1]);   // y is flipped in Vulkan
	float seen = length(origin - CAMERA_POSITION_WORLD) / max(zoom, 0.01);
	float keep = seen <= full_density_m ? 1.0 : pow(full_density_m / seen, thin_exponent);
	keep /= pow(max(zoom, 1.0), zoom_thin_exponent);   // flatter look along the ground
	float widen = clamp(inversesqrt(max(keep, 1e-4)), 1.0, max_widen);
	far_flat = smoothstep(full_density_m, flat_colour_m, seen);
	keep *= 1.0 - smoothstep(blade_range_m * 0.75, blade_range_m, seen);
	float rank = INSTANCE_CUSTOM.r;
	if (rank >= keep) {
		VERTEX = vec3(0.0);
	} else {
		// Clumps only turn about y and scale in height (MultiMesh transforms), so in model
		// space widening is x/z, growing is y, and a sideways world offset is the turned-back
		// offset (transpose of the basis).
		float grow = 1.0 - smoothstep(keep * 0.7, keep, rank);
		VERTEX.xz *= widen;
		VERTEX.y *= grow;
		vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float t = TIME * 1.6 + dot(world.xz, vec2(0.21, 0.13));
		float gust = sin(t) * 0.7 + sin(t * 2.3 + 1.7) * 0.3;
		vec3 sway = vec3(wind_dir.x, 0.0, wind_dir.y) * gust * sway_m * tip * tip;
		VERTEX += transpose(mat3(MODEL_MATRIX)) * sway;
	}
	world_pos = origin;
	// up in the world after the normal matrix (the basis' y scale only shortens it)
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	// patchy like the far canopy (same noise), so near and far fields match
	float n = noise2(world_pos.xz * 0.045) * 0.65 + noise2(world_pos.xz * 0.21) * 0.35;
	ALBEDO = COLOR.rgb * (0.78 + 0.4 * n) * mix(mix(base_darkness, 1.0, tip), 0.8, far_flat);
	ROUGHNESS = 0.95;
	BACKLIGHT = vec3(0.18, 0.22, 0.08) * mix(tip, 0.5, far_flat);
}
