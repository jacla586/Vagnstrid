shader_type spatial;
// Track runs with links that move: raised grousers across the track every `pitch`
// metres, shifted by how far each track has rolled (TankLooks: track_dist_l/r, m). The
// top run moves forward and the bottom run back relative to the hull, the ends around.
// Model space (hull frame: -Z forward). The bottom run follows the ground under it like
// the road wheels (TankLooks: ground_fit, see tank_wheel.gdshader): CUSTOM0.x is the
// track bottom, CUSTOM0.y the height from which up nothing moves.

uniform vec3 albedo : source_color = vec3(0.13, 0.12, 0.11);
uniform vec3 grouser : source_color = vec3(0.22, 0.21, 0.19);
uniform float pitch = 0.17;
uniform float roughness_value = 1.0;

instance uniform float track_dist_l : instance_index(5) = 0.0;
instance uniform float track_dist_r : instance_index(6) = 0.0;
instance uniform vec4 ground_fit : instance_index(7) = vec4(0.0);

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	float span = CUSTOM0.y - CUSTOM0.x;
	if (span > 0.0) {
		float w = clamp((CUSTOM0.y - VERTEX.y) / span, 0.0, 1.0);
		vec2 fit = VERTEX.x < 0.0 ? ground_fit.xy : ground_fit.zw;
		VERTEX.y += w * (fit.x + fit.y * VERTEX.z);
	}
}

void fragment() {
	vec3 n = normalize(local_normal);
	float dist = local_pos.x < 0.0 ? track_dist_l : track_dist_r;
	vec3 col = albedo;
	if (abs(n.x) < 0.6) {
		// Along the run: z on the top and bottom, height on the ends.
		float s;
		if (abs(n.y) >= abs(n.z)) {
			s = local_pos.z + (n.y > 0.0 ? dist : -dist);
		} else {
			s = local_pos.y * sign(n.z) + (n.z > 0.0 ? dist : -dist);
		}
		float f = fract(s / pitch);
		float w = max(fwidth(s / pitch), 0.001);
		float bar = smoothstep(0.0, w, f) * (1.0 - smoothstep(0.35 - w, 0.35, f));
		col = mix(albedo, grouser, bar);
	} else {
		// The outer faces: link edges, a little lighter.
		float f = fract(local_pos.z / pitch);
		col = mix(albedo, grouser, step(0.88, f) * 0.5);
	}
	ALBEDO = col;
	ROUGHNESS = roughness_value;
}
