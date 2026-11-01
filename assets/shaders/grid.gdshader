shader_type spatial;
// Simple world-space grid so movement is visible on the flat test ground.

uniform vec4 base_color : source_color = vec4(0.36, 0.42, 0.30, 1.0);
uniform vec4 line_color : source_color = vec4(0.22, 0.26, 0.18, 1.0);
uniform float cell_size = 10.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = world_pos.xz / cell_size;
	vec2 grid = abs(fract(cell - 0.5) - 0.5) / fwidth(cell);
	float line = 1.0 - min(min(grid.x, grid.y), 1.0);
	ALBEDO = mix(base_color.rgb, line_color.rgb, line);
	ROUGHNESS = 0.95;
}
