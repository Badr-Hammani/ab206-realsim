shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// Runway / taxiway surface with painted markings, drawn from UVs:
// UV.x = metres across from the centreline (-w/2 .. +w/2), UV.y = metres along from the start.
// kind 0 = runway (ICAO-style white markings), 1 = taxiway (yellow centreline), 2 = apron (plain).
uniform int kind = 0;
uniform float length_m = 2400.0;
uniform float width_m = 45.0;
uniform vec3 asphalt = vec3(0.20, 0.20, 0.21);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = vnoise(wpos.xz * 0.7) * 0.5 + vnoise(wpos.xz * 0.09) * 0.5;
	vec3 col = asphalt * (0.85 + 0.3 * n);
	float x = abs(UV.x);
	float y = UV.y;
	float paint = 0.0;
	vec3 paint_col = vec3(0.92, 0.92, 0.90);
	if (kind == 0) {
		float yy = min(y, length_m - y);          // distance from the nearer end
		paint += step(width_m * 0.5 - 1.6, x) * step(x, width_m * 0.5 - 0.7);      // edge lines
		if (yy > 6.0 && yy < 36.0)                                           // threshold "piano keys"
			paint += step(1.8, x) * step(x, width_m * 0.5 - 3.0) * step(fract((x - 1.8) / 3.6), 0.5);
		if (yy > 300.0 && yy < 345.0)                                        // aiming point
			paint += step(6.0, x) * step(x, 16.0);
		if (yy > 150.0 && yy < 172.0 || yy > 450.0 && yy < 472.0 || yy > 600.0 && yy < 622.0)  // touchdown zone
			paint += step(6.0, x) * step(x, 9.0) + step(11.0, x) * step(x, 14.0);
		if (yy > 75.0)                                                       // centreline dashes 30 m / 20 m
			paint += step(x, 0.45) * step(fract(y / 50.0), 0.6);
	} else if (kind == 1) {
		paint += step(x, 0.15);
		paint_col = vec3(0.95, 0.75, 0.10);
		col = mix(col, col * 0.8 + vec3(0.03), step(width_m * 0.5 - 1.0, x));
	}
	col = mix(col, paint_col * (0.9 + 0.1 * n), clamp(paint, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = 0.9;
}
