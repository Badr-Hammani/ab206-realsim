shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// Height/slope based terrain colouring with distance-faded fine detail so
// height and motion cues work in the hover (important for learning to hover).
uniform int detail = 1;

varying vec3 wpos;
varying vec3 wnorm;

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
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float slope = 1.0 - wnorm.y;
	float n1 = vnoise(wpos.xz / 60.0);
	float n2 = vnoise(wpos.xz / 9.0);
	vec3 grass_a = vec3(0.24, 0.33, 0.14);
	vec3 grass_b = vec3(0.36, 0.40, 0.18);
	vec3 rock = vec3(0.42, 0.40, 0.37);
	vec3 dirt = vec3(0.40, 0.34, 0.24);
	vec3 snow = vec3(0.92, 0.93, 0.96);
	vec3 col = mix(grass_a, grass_b, n1 * 0.7 + n2 * 0.3);
	col = mix(col, dirt, smoothstep(0.55, 0.85, n1) * 0.35);
	float alpine = smoothstep(820.0, 1000.0, wpos.y + n1 * 60.0);
	col = mix(col, vec3(0.33, 0.33, 0.27), alpine * 0.6);
	col = mix(col, rock, smoothstep(0.28, 0.45, slope + (n2 - 0.5) * 0.12));
	col = mix(col, snow, smoothstep(1120.0, 1180.0, wpos.y + n1 * 80.0) * (1.0 - smoothstep(0.45, 0.6, slope)));
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	if (detail > 0) {
		float fine = vnoise(wpos.xz * 1.3) * 0.6 + vnoise(wpos.xz * 0.35) * 0.4;
		float fade = 1.0 - smoothstep(30.0, 180.0, dist);
		col *= mix(1.0, 0.78 + fine * 0.44, fade);
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
