shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, cull_disabled;

// Buildings found in the 0.5 m aerial photo (scripts/world/ai_features.gd). Real footprints, so the
// roof shows the HD aerial photo itself where it is loaded (it lines up with the walls), else the
// roof colour measured in the photo. Walls: render colour with floors of windows.
// COLOR = roof colour (rgb). UV = (metres along the wall, metres above the base). UV2.x = height.
#include "res://shaders/hd_ground.gdshaderinc"

varying vec3 wpos;
varying vec3 wn;
varying float cam_dist;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	cam_dist = length(wpos - CAMERA_POSITION_WORLD);
}

void fragment() {
	vec3 roof = COLOR.rgb;
	float far = smoothstep(350.0, 900.0, cam_dist);
	vec3 col;
	if (wn.y > 0.5) {
		vec4 hd = hd_sample(wpos, CAMERA_POSITION_WORLD);
		col = mix(roof * 0.6, hd.rgb * 0.82, hd.a);
		ROUGHNESS = 0.95;
	} else {
		float h = UV2.x;
		float up = UV.y;
		float u = UV.x;
		float seed = hash(floor(wpos.xz / 7.0));
		// walls: a lighter, less saturated version of the roof colour (Moroccan render)
		// Khouribga render is warm: ochre, sand and salmon, never blue-white
		vec3 warm = mix(vec3(0.80, 0.60, 0.40), vec3(0.84, 0.56, 0.45), seed);
		vec3 wall = mix(warm, roof * 0.8, 0.15);
		float storey = floor(up / 3.1);
		float in_floor = up - storey * 3.1;
		float bay = fract(u / 3.4);
		float win = step(0.3, bay) * step(bay, 0.68) * step(0.95, in_floor) * step(in_floor, 2.25);
		win *= step(0.8, up) * step(up, h - 1.0);
		float lit = hash(vec2(floor(u / 3.4), storey) + seed * 13.0);
		vec3 glass = mix(vec3(0.09, 0.10, 0.12), vec3(0.26, 0.29, 0.32), lit);
		col = mix(wall, glass, win * (1.0 - far));
		col = mix(col, col * 0.86, far * 0.5);
		col *= 0.74 + 0.26 * smoothstep(0.0, 1.6, up);
		ROUGHNESS = mix(0.9, 0.3, win * (1.0 - far));
		// warm light bounced up from the dry ochre ground (the blue sky alone made walls lavender)
		EMISSION = wall * vec3(0.20, 0.15, 0.09) * (1.0 - win * (1.0 - far));
	}
	ALBEDO = col;
	// lighting from our own flat normal (cull_disabled would flip it on back-wound faces)
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
