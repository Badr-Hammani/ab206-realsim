shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// Real-map terrain: a cloud-free Sentinel-2 photo (10 m, natural colour) draped over the DEM.
// Close to the camera, where 10 m pixels would look blurry, the photo's own colour drives
// generated ground detail: soil grain, small stones, dry grass tufts on green/yellow ground and
// faint plough lines on bare fields. It fades out with distance so far views stay the real photo.
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

// sparse round blobs (stones / tufts) of radius r in cells of size 1
float blobs(vec2 p, float density, float r) {
	vec2 c = floor(p);
	vec2 f = fract(p);
	float h = hash(c + 17.0);
	vec2 o = vec2(hash(c + 3.1), hash(c + 7.7)) * (1.0 - 2.0 * r) + r;
	float d = length(f - o);
	return step(h, density) * (1.0 - smoothstep(r * 0.6, r, d));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (wpos.xz + vec2(map_size * 0.5)) / map_size;
	vec3 col = texture(photo, uv).rgb;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	float green = clamp((col.g - max(col.r, col.b)) * 6.0 + 0.3, 0.0, 1.0);
	// medium-scale variation (5-40 m) breaks the 10 m pixel look from low altitude
	float med = vnoise(wpos.xz / 23.0) * 0.6 + vnoise(wpos.xz / 6.5) * 0.4;
	col *= mix(1.0, 0.9 + 0.2 * med, 1.0 - smoothstep(300.0, 1500.0, dist));
	if (detail > 0) {
		float near = 1.0 - smoothstep(20.0, 160.0, dist);
		if (near > 0.0) {
			float grain = vnoise(wpos.xz * 2.7) * 0.5 + vnoise(wpos.xz * 0.9) * 0.3 + vnoise(wpos.xz * 0.27) * 0.2;
			vec3 d = col * (0.78 + 0.44 * grain);
			// stones: lighter/darker speckles on bare ground
			vec2 jit = wpos.xz * 1.6 + vec2(vnoise(wpos.xz * 0.5), vnoise(wpos.xz * 0.5 + 9.0)) * 1.7;
			float st = blobs(jit, 0.05 * (1.0 - green), 0.22);
			d = mix(d, col * (hash(floor(jit)) > 0.5 ? 1.25 : 0.75), st * 0.6);
			// tufts of grass/stubble where the photo is green or straw-coloured
			vec2 jt = wpos.xz * 1.1 + vec2(vnoise(wpos.xz * 0.4 + 3.0), vnoise(wpos.xz * 0.4 + 5.0)) * 2.0;
			float tuft = blobs(jt, 0.22 * green + 0.03, 0.40) * (0.5 + 0.5 * vnoise(wpos.xz * 3.0));
			d = mix(d, col * vec3(0.78, 0.88, 0.62), tuft * 0.45);
			// faint plough lines on bare fields (orientation varies per 60 m patch)
			float ang = hash(floor(wpos.xz / 60.0)) * 3.1416;
			float fur = sin(dot(wpos.xz, vec2(cos(ang), sin(ang))) * 6.28 / 0.9);
			d *= 1.0 - 0.07 * (1.0 - green) * smoothstep(0.2, 1.0, fur) * step(0.18, lum);
			col = mix(col, d, near);
		}
	} else {
		float fine = vnoise(wpos.xz * 0.33);
		col *= mix(1.0, 0.86 + fine * 0.28, 1.0 - smoothstep(20.0, 120.0, dist));
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
