shader_type spatial;
// The far ground vegetation near the blade field's edge or seen from above (GroundCoverCanopy):
// dithered in where the blades thin out (fade_in_start..fade_in_end seen distance from the camera:
// true distance / zoom, as the blades count it), and thinned when
// looked down on, as GroundCover's rule (full to grazing_full_deg below the horizon, none from
// grazing_none_deg). See ground_cover_canopy.gdshaderinc.
render_mode cull_disabled, diffuse_lambert, specular_disabled;
#include "res://assets/shaders/ground_cover_canopy.gdshaderinc"

uniform float fade_in_start = 96.0;
uniform float fade_in_end = 144.0;
uniform float ref_tan_half = 0.7;
uniform float grazing_full_deg = 4.0;
uniform float grazing_none_deg = 35.0;

void fragment() {
	float d = length(world_pos - CAMERA_POSITION_WORLD);
	float zoom = max(ref_tan_half * abs(PROJECTION_MATRIX[1][1]), 0.01);   // y is flipped in Vulkan
	float a = smoothstep(fade_in_start, fade_in_end, d / zoom);
	float down_deg = degrees(asin(clamp((CAMERA_POSITION_WORLD.y - world_pos.y) / max(d, 0.01), -1.0, 1.0)));
	a *= 1.0 - smoothstep(grazing_full_deg, grazing_none_deg, down_deg);
	int x = int(FRAGCOORD.x) % 4;
	int y = int(FRAGCOORD.y) % 4;
	float bayer[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	if (a < (bayer[y * 4 + x] + 0.5) / 16.0) {
		discard;
	}
	ALBEDO = canopy_albedo();
	ROUGHNESS = 1.0;
}
