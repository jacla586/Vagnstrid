shader_type spatial;
// Enemy camouflage after the Swedish M90: angular splinter fields in light green, mid
// green, dark green and black, all leaning the same way. Built from the mesh's own
// (model-space) coordinates, so the pattern sticks to the vehicle or soldier; each face
// is projected along its main axis. Flat colours to match the low-poly look.
//
// The fields are Voronoi cells in a rotated, stretched space (so their straight edges
// lean together and they come out as long shards, not little spiky triangles), and a
// second, finer layer adds the black splinters. Borders are blended over one pixel
// (fwidth), so edges stay clean instead of stair-stepped at a distance.

uniform vec3 color_base : source_color = vec3(0.56, 0.60, 0.42);  // light green
uniform vec3 color_a : source_color = vec3(0.33, 0.42, 0.25);     // mid green
uniform vec3 color_b : source_color = vec3(0.17, 0.25, 0.15);     // dark green
uniform vec3 color_c : source_color = vec3(0.08, 0.09, 0.07);     // black
// Fields per metre of model space (scale it for models not in metres).
uniform float pattern_scale = 0.75;
// Share of the fields in mid and dark green (the rest is light green), and of the fine
// layer's cells that are black.
uniform float cover_a = 0.36;
uniform float cover_b = 0.30;
uniform float cover_c = 0.22;
// How long the shards are for their width, and which way they lean (radians).
uniform float stretch = 2.6;
uniform float lean = 0.5;
uniform float roughness_value = 0.85;

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

#include "res://assets/shaders/m90.gdshaderinc"

void fragment() {
	ALBEDO = m90_colour(face_uv(local_pos * pattern_scale, local_normal));
	ROUGHNESS = roughness_value;
}
