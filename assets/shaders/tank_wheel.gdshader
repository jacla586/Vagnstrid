shader_type spatial;
// Road wheels, sprockets and idlers that turn as the tank drives. Each wheel vertex
// carries its wheel's centre (y, z) and 1/radius in CUSTOM0 (MeshKit.spin); the left and
// right wheels turn by how far their track has rolled (TankLooks: wheel_dist_l/r, m).

uniform vec3 albedo : source_color = vec3(0.2, 0.21, 0.18);
uniform float roughness_value = 0.9;

instance uniform float wheel_dist_l = 0.0;
instance uniform float wheel_dist_r = 0.0;

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
	}
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = roughness_value;
}
