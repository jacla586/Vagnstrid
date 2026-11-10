shader_type spatial;
// The back of a road or place-name sign (geodata materials *_bak, PropBreak swaps them in):
// the sign's outline from the face texture's alpha, but plain galvanised sheet metal, so
// no mirrored text shows through. A faint brushed streak and darker rim near the edge.
render_mode cull_back;

uniform sampler2D face_texture : source_color, filter_linear_mipmap;
uniform vec3 metal_color : source_color = vec3(0.62, 0.64, 0.66);
uniform float alpha_cut = 0.5;

void fragment() {
	vec4 face = texture(face_texture, UV);
	ALPHA = face.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	// the rim: where the alpha of nearby texels falls off (cheap: the derivative of alpha)
	float rim = clamp(fwidth(face.a) * 3.0, 0.0, 1.0);
	float streak = 0.96 + 0.04 * sin(UV.y * 900.0);
	ALBEDO = metal_color * streak * mix(1.0, 0.7, rim);
	METALLIC = 0.3;
	ROUGHNESS = 0.55;
}
