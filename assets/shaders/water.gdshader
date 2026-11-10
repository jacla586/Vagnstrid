shader_type spatial;
// Lakes, streams and the sea (WaterLook puts it on the map's water meshes). Colour by the water's
// thickness over the bottom (depth buffer): clear and greenish at the shore, dark further out, a pale
// rim where it meets the ground; two scrolling normal maps drift with the wind, rain adds fine rings.
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 deep_color : source_color = vec3(0.06, 0.13, 0.15);
uniform vec3 shallow_color : source_color = vec3(0.22, 0.30, 0.25);
uniform float depth_fade_m = 2.5;
uniform float foam_width_m = 0.3;
uniform vec3 foam_color : source_color = vec3(0.72, 0.76, 0.72);
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec2 wind = vec2(1.0, 0.4);
uniform float wave_scale = 0.07;
uniform float rain = 0.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz * wave_scale;
	vec3 n1 = texture(normal_a, uv + wind * TIME * 0.015).rgb * 2.0 - 1.0;
	vec3 n2 = texture(normal_b, uv * 2.3 - vec2(wind.y, wind.x) * TIME * 0.025).rgb * 2.0 - 1.0;
	vec3 n = normalize(n1 + n2);
	vec3 n3 = texture(normal_b, wpos.xz * 0.9 + vec2(TIME * 0.31, -TIME * 0.23)).rgb * 2.0 - 1.0;
	n = normalize(n + n3 * rain * 0.9);
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.5 + rain * 0.4;

	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	view.xyz /= view.w;
	float thickness = max(-view.z - (-VERTEX.z), 0.0);
	float t = clamp(thickness / depth_fade_m, 0.0, 1.0);
	float foam = 1.0 - smoothstep(0.0, foam_width_m, thickness);
	ALBEDO = mix(mix(shallow_color, deep_color, t), foam_color, foam * 0.55);
	ALPHA = clamp(mix(0.5, 0.94, t) + foam * 0.3, 0.0, 1.0);
	ROUGHNESS = 0.05 + rain * 0.2;
	SPECULAR = 0.6;
}
