shader_type canvas_item;
// Dirt thrown over the optics by a near HE burst (OpticsDirt): brown splashes, thicker
// towards the edges, a few big clots and fine specks; `amount` 0..1 fades it out (the
// thinnest parts clear first, so it looks like the dirt slides off, not like a fade).

uniform float amount = 0.0;
uniform float aspect = 1.78;
uniform vec2 seed = vec2(0.0);
uniform vec3 dirt_color : source_color = vec3(0.23, 0.17, 0.11);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = vec2((UV.x - 0.5) * aspect, UV.y - 0.5);
	vec2 q = p * 3.0 + seed;
	// splashes: blotchy noise, denser away from the centre
	float edge = smoothstep(0.15, 0.95, length(p * vec2(0.8, 1.15)));
	float blot = fbm(q + fbm(q * 1.7) * 0.8);
	float specks = step(0.93, noise(p * 70.0 + seed * 3.0)) * 0.8;
	float d = clamp((blot - 0.62 + edge * 0.45) * 3.0, 0.0, 1.0) + specks * edge;
	// thin parts clear first as the dirt fades
	float a = smoothstep(1.0 - amount, 1.0 - amount + 0.25, d * 0.95) * min(amount * 1.6, 1.0);
	// a faint dusty film over everything while fresh
	a = max(a, amount * 0.18);
	vec3 col = dirt_color * (0.75 + 0.5 * blot);
	COLOR = vec4(col, clamp(a, 0.0, 0.97));
}
