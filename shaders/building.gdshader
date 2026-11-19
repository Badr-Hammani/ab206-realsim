shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// Houses of a real map (one unit box per instance, MultiMesh). INSTANCE_CUSTOM = (r, g, b, height m).
// Walls get floors of windows (and shop fronts on some ground floors), roofs a parapet and
// small roof clutter. Window detail fades out with distance so it never shimmers.

varying vec3 lpos;          // metres from the box centre, along the box axes
varying vec3 lnorm;
varying vec3 base_col;
varying float bh;
varying float seed;
varying float cam_dist;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	lpos = VERTEX * sc;
	lnorm = NORMAL;
	base_col = INSTANCE_CUSTOM.rgb;
	bh = INSTANCE_CUSTOM.a;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	seed = hash(floor(MODEL_MATRIX[3].xz));
	cam_dist = length(w - CAMERA_POSITION_WORLD);
}

void fragment() {
	vec3 col = base_col;
	float up = lpos.y + bh * 0.5;                 // metres above the bottom of the box
	float far = smoothstep(350.0, 900.0, cam_dist);
	if (lnorm.y > 0.5) {
		// flat roof: parapet band, a few water tanks / dishes, weathering
		vec2 half_size = vec2(abs(lpos.x), abs(lpos.z));
		float n = hash(floor(lpos.xz * 0.8) + seed * 31.0);
		col *= 0.86 + 0.08 * n;
		float clutter = step(0.985, hash(floor(lpos.xz * 0.5) + seed * 7.0));
		col = mix(col, vec3(0.92, 0.92, 0.95), clutter * (1.0 - far));
		ROUGHNESS = 0.95;
	} else if (lnorm.y < -0.5) {
		col *= 0.4;
	} else {
		float u = abs(lnorm.x) > 0.5 ? lpos.z : lpos.x;
		float storey = floor(up / 3.1);
		float in_floor = up - storey * 3.1;
		float bay = fract((u + 50.0) / 3.4);
		float win = step(0.3, bay) * step(bay, 0.68) * step(0.95, in_floor) * step(in_floor, 2.25);
		win *= step(0.8, up) * step(up, bh - 1.2);           // not in the parapet, not under ground
		float shop = step(0.55, seed) * step(up, 3.0) * step(0.62, up) * step(0.15, bay) * step(bay, 0.85);
		float lit = hash(vec2(floor((u + 50.0) / 3.4), storey) + seed * 13.0);
		vec3 glass = mix(vec3(0.10, 0.12, 0.15), vec3(0.28, 0.32, 0.36), lit);
		float detail_w = (1.0 - far);
		col = mix(col, glass, max(win, shop * 0.85) * detail_w);
		col = mix(col, col * 0.84, far * 0.5);                  // average of windows far away
		col *= 0.72 + 0.28 * smoothstep(0.0, 1.6, up);          // dirt and shade at the foot of the wall
		col *= mix(1.0, 0.93, step(bh - 1.0, up));              // parapet line
		ROUGHNESS = mix(0.9, 0.25, win * detail_w);
	}
	ALBEDO = col;
}
