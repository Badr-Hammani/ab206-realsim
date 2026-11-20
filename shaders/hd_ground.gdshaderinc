// HD aerial photo streamed live around the helicopter (scripts/world/hd_ground.gd).
// Three levels: "u" = zoom 18 (~0.5 m) right around you, "n" = zoom 17 web tiles (~1 m per pixel) close in, "f" = zoom 15 (~4 m) further out.
// Each level is a ring buffer of 256 x 256 tiles in a texture array: a tile at web tile (tx, ty)
// lives in slot (tx mod w, ty mod w). hd_idx_* says which tile each slot holds right now, so a slot
// that still holds an old tile (or nothing) is ignored and the Sentinel-2 photo shows instead.
// World x/z -> tile coordinates is an affine fit (hd_ax/hd_ay) refreshed by the script as you fly.
uniform float hd_on = 0.0;
uniform sampler2DArray hd_tex_n : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D hd_idx_n : filter_nearest, repeat_disable;
uniform vec3 hd_ax_n = vec3(0.0);
uniform vec3 hd_ay_n = vec3(0.0);
uniform float hd_w_n = 1.0;
uniform vec2 hd_bm_n = vec2(0.0);
uniform float hd_r_n = 0.0;       // fade-out distance (m) of the near level
uniform sampler2DArray hd_tex_f : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D hd_idx_f : filter_nearest, repeat_disable;
uniform vec3 hd_ax_f = vec3(0.0);
uniform vec3 hd_ay_f = vec3(0.0);
uniform float hd_w_f = 1.0;
uniform vec2 hd_bm_f = vec2(0.0);
uniform float hd_r_f = 0.0;
// "u" = zoom 18 (~0.5 m per pixel) right around the helicopter (High and Ultra presets)
uniform sampler2DArray hd_tex_u : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D hd_idx_u : filter_nearest, repeat_disable;
uniform vec3 hd_ax_u = vec3(0.0);
uniform vec3 hd_ay_u = vec3(0.0);
uniform float hd_w_u = 1.0;
uniform vec2 hd_bm_u = vec2(0.0);
uniform float hd_r_u = 0.0;

vec4 hd_level(sampler2DArray tex, sampler2D idx, vec2 t, vec2 gx, vec2 gy, float w, vec2 bm) {
	vec2 tf = floor(t);
	vec2 slot = mod(tf + bm, vec2(w));
	vec2 have = texelFetch(idx, ivec2(slot), 0).rg;
	if (abs(have.x - tf.x) > 0.25 || abs(have.y - tf.y) > 0.25)
		return vec4(0.0);
	vec2 uv = clamp(t - tf, vec2(0.5 / 256.0), vec2(255.5 / 256.0));
	// gradients x0.6: about 0.7 mip level sharper than default (anisotropic filtering keeps it clean)
	vec3 c = textureGrad(tex, vec3(uv, slot.y * w + slot.x), gx * 0.6, gy * 0.6).rgb;
	return vec4(c, 1.0);
}

// Returns the HD colour (rgb) and its weight (a, 0 = no HD here).
vec4 hd_sample(vec3 wp, vec3 cam) {
	if (hd_on < 0.5)
		return vec4(0.0);
	vec3 p = vec3(wp.x, wp.z, 1.0);
	vec2 tn = vec2(dot(hd_ax_n, p), dot(hd_ay_n, p));
	vec2 tf = vec2(dot(hd_ax_f, p), dot(hd_ay_f, p));
	// derivatives taken before any branch (texture lookups across tile edges stay smooth)
	vec2 nx = dFdx(tn);
	vec2 ny = dFdy(tn);
	vec2 fx = dFdx(tf);
	vec2 fy = dFdy(tf);
	vec2 tu = vec2(dot(hd_ax_u, p), dot(hd_ay_u, p));
	vec2 ux = dFdx(tu);
	vec2 uy = dFdy(tu);
	vec2 d = abs(wp.xz - cam.xz);
	float cheb = max(d.x, d.y);
	vec4 res = vec4(0.0);
	if (hd_r_f > 0.0 && cheb < hd_r_f) {
		vec4 c = hd_level(hd_tex_f, hd_idx_f, tf, fx, fy, hd_w_f, hd_bm_f);
		res = vec4(c.rgb, c.a * (1.0 - smoothstep(hd_r_f * 0.8, hd_r_f, cheb)));
	}
	if (hd_r_n > 0.0 && cheb < hd_r_n) {
		vec4 c = hd_level(hd_tex_n, hd_idx_n, tn, nx, ny, hd_w_n, hd_bm_n);
		float a = c.a * (1.0 - smoothstep(hd_r_n * 0.75, hd_r_n, cheb));
		res = vec4(mix(res.rgb, c.rgb, a / max(a + res.a * (1.0 - a), 1e-4)), a + res.a * (1.0 - a));
	}
	if (hd_r_u > 0.0 && cheb < hd_r_u) {
		vec4 c = hd_level(hd_tex_u, hd_idx_u, tu, ux, uy, hd_w_u, hd_bm_u);
		float a = c.a * (1.0 - smoothstep(hd_r_u * 0.7, hd_r_u, cheb));
		res = vec4(mix(res.rgb, c.rgb, a / max(a + res.a * (1.0 - a), 1e-4)), a + res.a * (1.0 - a));
	}
	return res;
}
