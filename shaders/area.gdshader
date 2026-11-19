shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;

// Real land-use areas from OpenStreetMap, draped on the terrain (scripts/world/khouribga.gd _areas).
// UV2.x = kind: 0 park / grass, 1 sports pitch, 2 cemetery, 3 school or hospital yard.
// Pitches: UV = metres along / across the pitch from its centre, UV2.y = length * 1000 + width.
// Every kind starts from the satellite photo so the colours stay close to the real ground.
uniform sampler2D photo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float map_size = 16384.0;
#include "res://shaders/hd_ground.gdshaderinc"

varying vec3 wpos;
varying vec2 local;
varying flat int kind;
varying vec2 dims;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float line(float d, float w) {
	float aa = max(fwidth(d), 0.02);
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + aa, abs(d));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local = UV;
	kind = int(UV2.x + 0.5);
	dims = vec2(floor(UV2.y / 1000.0), mod(UV2.y, 1000.0));
}

void fragment() {
	vec2 uv = (wpos.xz + vec2(map_size * 0.5)) / map_size;
	vec3 ph = texture(photo, uv).rgb;
	// where the live HD photo is showing, the real park / pitch / cemetery is in the photo itself
	if (hd_sample(wpos, CAMERA_POSITION_WORLD).a > 0.5)
		discard;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float n = hash(floor(wpos.xz * 0.7));
	vec3 col = ph;
	if (kind == 0) {
		col = mix(ph, vec3(0.30, 0.38, 0.20) * (0.85 + 0.3 * n), 0.45);
	} else if (kind == 1) {
		float L = dims.x;
		float W = dims.y;
		float s = clamp(L / 105.0, 0.3, 1.0);
		float stripe = step(0.5, fract(local.x / (L / 12.0)));
		col = mix(ph, vec3(0.26, 0.42, 0.19) * (0.92 + 0.1 * stripe), 0.55);
		float hl = L * 0.5 - 1.5;
		float hw = W * 0.5 - 1.5;
		float w = 0.18;
		float m = 0.0;
		// touch lines and goal lines
		m = max(m, line(abs(local.x) - hl, w) * step(abs(local.y), hw + w));
		m = max(m, line(abs(local.y) - hw, w) * step(abs(local.x), hl + w));
		// halfway line and centre circle
		m = max(m, line(local.x, w) * step(abs(local.y), hw));
		m = max(m, line(length(local) - 9.15 * s, w));
		// penalty areas
		float pd = 16.5 * s;
		float pw = min(20.15 * s, hw);
		m = max(m, line(abs(local.x) - (hl - pd), w) * step(abs(local.y), pw));
		m = max(m, line(abs(local.y) - pw, w) * step(hl - pd, abs(local.x)) * step(abs(local.x), hl));
		col = mix(col, vec3(0.92), m * (1.0 - smoothstep(250.0, 700.0, dist)));
	} else if (kind == 2) {
		// pale earth with rows of white-washed graves
		col = mix(ph, vec3(0.70, 0.64, 0.54), 0.35);
		vec2 c = wpos.xz / vec2(1.4, 2.6);
		vec2 f = fract(c);
		float g = step(0.3, f.x) * step(f.x, 0.75) * step(0.15, f.y) * step(f.y, 0.85) * step(0.35, hash(floor(c)));
		col = mix(col, vec3(0.86, 0.85, 0.82), g * (1.0 - smoothstep(120.0, 400.0, dist)) * 0.8);
	} else {
		col = mix(ph, vec3(0.74, 0.69, 0.60) * (0.9 + 0.15 * n), 0.4);
	}
	ALBEDO = col;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);   // flat ground, either winding
	ROUGHNESS = 0.95;
}
