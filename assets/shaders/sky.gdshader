shader_type sky;
// Sky for WeatherView: a zenith-to-horizon gradient that warms towards a low sun (dawn,
// dusk), a sun disc and halo from the first DirectionalLight3D, and two drifting layers
// of noise clouds lit from the sun's side. Clouds are left out of the radiance cubemap
// (ambient light, reflections), which keeps it cheap.

uniform vec3 zenith_color : source_color = vec3(0.2, 0.4, 0.78);
uniform vec3 horizon_color : source_color = vec3(0.66, 0.76, 0.88);
uniform vec3 ground_color : source_color = vec3(0.32, 0.33, 0.3);
uniform vec3 sunset_color : source_color = vec3(1.0, 0.55, 0.3);
uniform float sky_energy = 1.0;
uniform float sun_disc_scale = 1.0;
uniform float sun_halo = 0.35;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.38;
uniform float cloud_softness : hint_range(0.01, 1.0) = 0.3;
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.9;
uniform vec3 cloud_color : source_color = vec3(1.0);
uniform vec3 cloud_shade : source_color = vec3(0.56, 0.62, 0.72);
uniform float cloud_scale = 1.0;
// Cloud drift (uv per second).
uniform vec2 cloud_wind = vec2(0.002, 0.0008);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
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
	mat2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = r * p * 2.03;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 sun = LIGHT0_ENABLED ? LIGHT0_DIRECTION : vec3(0.0, 1.0, 0.0);
	vec3 sun_col = LIGHT0_ENABLED ? LIGHT0_COLOR : vec3(1.0);
	// 1 with the sun on the horizon, 0 when it is high.
	float low_sun = smoothstep(0.45, -0.05, sun.y);
	float lx = length(dir.xz);
	float ls = length(sun.xz);
	float toward = (lx > 1e-4 && ls > 1e-4) ? max(dot(dir.xz / lx, sun.xz / ls), 0.0) : 0.0;
	toward = toward * toward * toward;
	float h = max(dir.y, 0.0);
	vec3 horizon = mix(horizon_color, sunset_color, low_sun * (0.3 + 0.7 * toward));
	vec3 zenith = zenith_color * mix(1.0, 0.55, low_sun);
	vec3 col = mix(horizon, zenith, pow(smoothstep(0.0, 0.55, h), 0.7));
	col = mix(col, ground_color, smoothstep(0.0, -0.08, dir.y));
	float cosang = dot(dir, sun);
	float c0 = max(cosang, 0.0);
	col += sun_col * (pow(c0, 64.0) * sun_halo + pow(c0, 6.0) * sun_halo * 0.2 * (0.4 + low_sun));
	float disc_r = max(LIGHT0_SIZE * 0.5 * sun_disc_scale, 0.004);
	float ang = acos(clamp(cosang, -1.0, 1.0));
	float disc = 1.0 - smoothstep(disc_r * 0.75, disc_r, ang);
	if (!AT_CUBEMAP_PASS && dir.y > 0.0) {
		vec2 uv = dir.xz / (dir.y + 0.1) * cloud_scale;
		vec2 w = cloud_wind * TIME;
		float n = fbm(uv + w) * 0.65 + fbm(uv * 2.7 - w * 1.6 + 7.3) * 0.35;
		float edge = 1.0 - cloud_coverage;
		float c = smoothstep(edge - cloud_softness * 0.5, edge + cloud_softness * 0.5, n);
		// Thicker towards the sun = darker underside; thin edges glow.
		float n2 = fbm(uv + w + sun.xz * 0.06);
		float lit = clamp(0.55 + (n - n2) * 3.0, 0.0, 1.0);
		vec3 cc = mix(cloud_shade, cloud_color, lit);
		cc *= mix(vec3(1.0), sunset_color * 1.25, low_sun * 0.65);
		cc += sun_col * pow(c0, 10.0) * 0.6 * (1.0 - c);
		float fade = smoothstep(0.0, 0.12, dir.y);
		float a = c * cloud_opacity * fade;
		col = mix(col, cc, a);
		disc *= 1.0 - a;
	}
	col += sun_col * disc * 12.0 * step(-0.02, dir.y);
	COLOR = col * sky_energy;
}
