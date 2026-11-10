shader_type spatial;
// A traffic-light lens (PropBreak puts it on the Signal_* surfaces of the Trafikljus kinds).
// The lamp follows a fixed cycle from TIME; each MultiMesh instance's custom data says where
// its junction is in the cycle (r: offset as a share of the cycle) and which of the junction's
// two directions it serves (g: 0 or 1, half a cycle apart). Cosmetic, nothing is sent.
// Cycle per direction: red+yellow, green, yellow, red (through the all-red and the other
// direction's turn). Pedestrian lights (lamps 3, 4) cross the road their post stands at, so
// they walk while that road's traffic has red.

// 0 red, 1 yellow, 2 green, 3 pedestrian red, 4 pedestrian green
uniform int lamp = 0;
uniform vec3 lit_colour : source_color = vec3(1.0, 0.1, 0.05);
uniform float energy = 4.0;
uniform float off_share = 0.08;
uniform float green_s = 14.0;
uniform float yellow_s = 3.0;
uniform float red_yellow_s = 1.5;
uniform float all_red_s = 2.0;
uniform float walk_s = 8.0;

varying flat vec2 v_phase;

void vertex() {
	v_phase = INSTANCE_CUSTOM.rg;
}

void fragment() {
	float half_cycle = red_yellow_s + green_s + yellow_s + all_red_s;
	float cycle = 2.0 * half_cycle;
	float t = mod(TIME + v_phase.r * cycle + step(0.5, v_phase.g) * half_cycle, cycle);
	float green_end = red_yellow_s + green_s;
	float yellow_end = green_end + yellow_s;
	bool walk = t >= half_cycle && t < half_cycle + walk_s;
	bool on = false;
	if (lamp == 0) {
		on = t < red_yellow_s || t >= yellow_end;
	} else if (lamp == 1) {
		on = t < red_yellow_s || (t >= green_end && t < yellow_end);
	} else if (lamp == 2) {
		on = t >= red_yellow_s && t < green_end;
	} else if (lamp == 3) {
		on = !walk;
	} else {
		on = walk;
	}
	float lit = on ? 1.0 : 0.0;
	ALBEDO = lit_colour * mix(off_share, 0.7, lit);
	EMISSION = lit_colour * energy * lit;
	ROUGHNESS = 0.25;
	SPECULAR = 0.6;
}
