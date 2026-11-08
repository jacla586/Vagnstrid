shader_type canvas_item;
// Rain on the optics (RainGlass): drops that sit, grow and dry, and drops that run down,
// each bending the picture behind it. Only the drops are drawn (alpha = drop).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform float aspect = 1.7778;

float h21(vec2 p) {
	p = fract(p * vec2(233.34, 851.73));
	p += dot(p, p + 23.45);
	return fract(p.x * p.y);
}

// One layer of still drops: xy = bend, z = coverage.
vec3 still_drops(vec2 uv, float t, float cells) {
	vec2 g = uv * vec2(aspect, 1.0) * cells;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float r = h21(id);
	if (r > intensity * 0.55) {
		return vec3(0.0);
	}
	vec2 at = (vec2(h21(id + 3.1), h21(id + 7.7)) - 0.5) * 0.6;
	float life = fract(t * (0.08 + 0.12 * h21(id + 1.3)) + r * 7.0);
	float size = (0.12 + 0.18 * h21(id + 5.2)) * smoothstep(0.0, 0.15, life) * (1.0 - smoothstep(0.7, 1.0, life));
	vec2 d = f - at;
	float m = smoothstep(size, size * 0.7, length(d));
	return vec3(d / max(size, 0.001) * m, m);
}

// Running drops: columns, each with a drop sliding down and a thin wet trail.
vec3 running_drops(vec2 uv, float t, float cols) {
	vec2 g = uv * vec2(aspect, 1.0) * vec2(cols, cols * 0.25);
	float col = floor(g.x);
	float rc = h21(vec2(col, 17.0));
	if (rc > intensity * 0.6) {
		return vec3(0.0);
	}
	g.y += t * (0.3 + 0.5 * rc);
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float x = (h21(id + 2.0) - 0.5) * 0.5 + sin(g.y * 9.0 + rc * 6.0) * 0.04;
	vec2 d = vec2((f.x - x) * 4.0, f.y * 1.0 + 0.2);
	float size = 0.18;
	float m = smoothstep(size, size * 0.6, length(d));
	float trail = smoothstep(0.08, 0.0, abs(f.x - x) * 4.0) * smoothstep(0.2, 0.5, f.y) * 0.35;
	return vec3(d / size * m, max(m, trail));
}

void fragment() {
	float t = TIME;
	vec2 uv = SCREEN_UV;
	vec3 a = still_drops(uv, t, 9.0);
	vec3 b = still_drops(uv + 0.37, t * 1.3, 15.0);
	vec3 c = running_drops(uv, t, 7.0);
	vec2 bend = a.xy + b.xy + c.xy;
	float cover = clamp(a.z + b.z + c.z, 0.0, 1.0);
	vec3 col = textureLod(screen_tex, uv - bend * 0.02, 1.5).rgb;
	col *= 0.85 + 0.25 * clamp(-bend.y, 0.0, 1.0);   // lit from above, dark below
	COLOR = vec4(col, cover * 0.95);
}
