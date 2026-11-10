shader_type spatial;
// The far ground vegetation, opaque (GroundCoverCanopy uses it for pieces well beyond the blade
// field, seen along the ground). See ground_cover_canopy.gdshaderinc.
render_mode cull_disabled, diffuse_lambert, specular_disabled;
#include "res://assets/shaders/ground_cover_canopy.gdshaderinc"

void fragment() {
	ALBEDO = canopy_albedo();
	ROUGHNESS = 1.0;
}
