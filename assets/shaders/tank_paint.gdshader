shader_type spatial;
// A tank's paint (Tank.paint_visual): friends in olive with soft darker blotches (an
// older two-tone scheme; their UN-blue markings stay separate), enemies in M90
// camouflage. Both weathered: faded patches, rain streaks down the sides, dust on the
// upward faces (more the more the tank has driven, `dust_amount`), mud and splashes low
// down near the tracks, darker and shinier when wet (`wetness`). Model space, so the look
// sticks to the tank. Per-instance values are set by TankLooks.

uniform bool enemy = false;
// Friend scheme.
uniform vec3 friend_base : source_color = vec3(0.36, 0.40, 0.27);
uniform vec3 friend_blotch : source_color = vec3(0.24, 0.26, 0.17);
uniform float friend_blotch_scale = 0.45;
uniform float friend_blotch_cover = 0.42;
// Enemy M90 (see m90.gdshaderinc).
uniform vec3 color_base : source_color = vec3(0.56, 0.60, 0.42);
uniform vec3 color_a : source_color = vec3(0.33, 0.42, 0.25);
uniform vec3 color_b : source_color = vec3(0.17, 0.25, 0.15);
uniform vec3 color_c : source_color = vec3(0.08, 0.09, 0.07);
uniform float pattern_scale = 0.75;
uniform float cover_a = 0.36;
uniform float cover_b = 0.30;
uniform float cover_c = 0.22;
uniform float stretch = 2.6;
uniform float lean = 0.5;
// Weathering.
uniform vec3 dust_colour : source_color = vec3(0.58, 0.53, 0.43);
uniform vec3 mud_colour : source_color = vec3(0.22, 0.18, 0.13);
// Mud reaches this high above the track bottoms (m), splashes higher.
uniform float mud_height = 0.75;
uniform float roughness_value = 0.85;

// 0 = clean .. 1 = covered in dust (driving); 0 = dry .. 1 = soaked (rain).
instance uniform float dust_amount : instance_index(0) = 0.25;
instance uniform float wetness : instance_index(1) = 0.0;
// This mesh's local height of the track bottoms (mud measures from it).
instance uniform float base_y : instance_index(2) = -0.7;

varying vec3 local_pos;
varying vec3 local_normal;

#include "res://assets/shaders/m90.gdshaderinc"

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash1(i);
	float b = hash1(i + vec2(1.0, 0.0));
	float c = hash1(i + vec2(0.0, 1.0));
	float d = hash1(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.1 + 7.3) * 0.3 + vnoise(p * 4.3 + 1.7) * 0.15;
}

void fragment() {
	vec3 n = normalize(local_normal);
	vec2 uv = face_uv(local_pos, n);
	vec3 col;
	if (enemy) {
		col = m90_colour(uv * pattern_scale);
	} else {
		// Soft-edged blotches from smooth noise.
		float b = fbm(uv * friend_blotch_scale + 3.1);
		float w = max(fwidth(b), 0.002) * 1.5;
		col = mix(friend_base, friend_blotch, smoothstep(1.0 - friend_blotch_cover - w, 1.0 - friend_blotch_cover + w, b));
	}
	// Faded and touched-up patches.
	float fade = fbm(uv * 0.35 + 11.0) - 0.5;
	col *= 1.0 + fade * 0.16;
	// Rain streaks on the sides: long in height, thin across.
	if (abs(n.y) < 0.5) {
		float across = (abs(n.x) > abs(n.z)) ? local_pos.z : local_pos.x;
		float streak = vnoise(vec2(across * 9.0, local_pos.y * 0.6 + 4.0));
		col *= 1.0 - smoothstep(0.62, 0.9, streak) * 0.12;
	}
	// Dust on faces that look up.
	float up = smoothstep(0.35, 0.85, n.y);
	float dust = up * dust_amount * (0.55 + 0.45 * fbm(uv * 1.3 + 5.0));
	col = mix(col, dust_colour, clamp(dust, 0.0, 0.85));
	// Mud low down: a ragged edge, splashes above it.
	float h = local_pos.y - base_y;
	float ragged = fbm(uv * 2.2 + 19.0);
	float mud = 1.0 - smoothstep(mud_height * 0.5, mud_height, h + (ragged - 0.5) * 0.35);
	float splash = step(0.8, vnoise(uv * 6.0 + 3.0)) * (1.0 - smoothstep(mud_height, mud_height * 1.8, h));
	col = mix(col, mud_colour, clamp(max(mud * 0.85, splash * 0.7), 0.0, 1.0));
	// Wet: darker and shinier.
	col *= 1.0 - wetness * 0.3;
	ALBEDO = col;
	ROUGHNESS = mix(roughness_value, 0.35, wetness);
}
