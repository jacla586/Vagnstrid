shader_type spatial;
// Road wheels, sprockets and idlers that turn as the tank drives. Each wheel vertex
// carries its wheel's centre (y, z) and 1/radius in CUSTOM0 (MeshKit.spin); the left and
// right wheels turn by how far their track has rolled (TankLooks: wheel_dist_l/r, m).
// Road wheels (CUSTOM0.w 2) also ride up and down with the ground under the track
// (TankLooks: ground_fit = left offset at z 0, left slope, right offset, right slope).

uniform vec3 albedo : source_color = vec3(0.2, 0.21, 0.18);
uniform float roughness_value = 0.9;

instance uniform float wheel_dist_l : instance_index(3) = 0.0;
instance uniform float wheel_dist_r : instance_index(4) = 0.0;
instance uniform vec4 ground_fit : instance_index(7) = vec4(0.0);

void vertex() {
	if (CUSTOM0.w > 0.5) {
		float dist = VERTEX.x < 0.0 ? wheel_dist_l : wheel_dist_r;
		// Driving forward (-Z) the top of a wheel moves forward.
		float a = -dist * CUSTOM0.z;
		float c = cos(a);
		float s = sin(a);
		vec2 p = VERTEX.yz - CUSTOM0.xy;
		VERTEX.yz = CUSTOM0.xy + vec2(c * p.x - s * p.y, s * p.x + c * p.y);
		NORMAL.yz = vec2(c * NORMAL.y - s * NORMAL.z, s * NORMAL.y + c * NORMAL.z);
		if (CUSTOM0.w > 1.5) {
			vec2 fit = VERTEX.x < 0.0 ? ground_fit.xy : ground_fit.zw;
			VERTEX.y += fit.x + fit.y * CUSTOM0.y;
		}
	}
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = roughness_value;
}
