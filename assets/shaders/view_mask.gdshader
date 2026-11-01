shader_type canvas_item;
// Optics mask. mode 1 = periscope slit, mode 2 = binoculars (two circles).

uniform int mode = 0;
uniform vec2 rect_size = vec2(1920.0, 1080.0);
// Periscope window size as fractions of the rect's width/height.
uniform vec2 window_size = vec2(0.55, 0.22);
uniform vec4 mask_color : source_color = vec4(0.02, 0.02, 0.02, 1.0);

void fragment() {
	vec2 px = UV * rect_size;
	vec2 centre = rect_size * 0.5;
	float mask = 0.0;
	if (mode == 1) {
		vec2 half_window = window_size * rect_size * 0.5;
		vec2 d = abs(px - centre) - half_window;
		mask = smoothstep(-1.5, 1.5, max(d.x, d.y));
	} else if (mode == 2) {
		float r = rect_size.y * 0.44;
		vec2 offset = vec2(r * 0.6, 0.0);
		float d = min(length(px - centre + offset), length(px - centre - offset)) - r;
		mask = smoothstep(-r * 0.08, 0.0, d);
	}
	COLOR = vec4(mask_color.rgb, mask_color.a * mask);
}
