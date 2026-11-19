shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// Real-map terrain: Sentinel-2 satellite photo (8 m per pixel) draped over the DEM, with
// distance-faded fine detail so height and drift cues still work close to the ground in a hover.
uniform sampler2D photo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float map_size = 16384.0;
uniform int detail = 1;

varying vec3 wpos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (wpos.xz + vec2(map_size * 0.5)) / map_size;
	vec3 col = texture(photo, uv).rgb;
	// the photo already contains the sun's shading; soften it a little so the 3D lighting does not double it
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, 0.88) * 0.95;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	if (detail > 0) {
		float fine = vnoise(wpos.xz * 1.3) * 0.55 + vnoise(wpos.xz * 0.33) * 0.30 + vnoise(wpos.xz * 0.08) * 0.15;
		float fade = 1.0 - smoothstep(25.0, 220.0, dist);
		col *= mix(1.0, 0.80 + fine * 0.40, fade);
	} else {
		float fine = vnoise(wpos.xz * 0.33);
		col *= mix(1.0, 0.86 + fine * 0.28, 1.0 - smoothstep(20.0, 120.0, dist));
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
