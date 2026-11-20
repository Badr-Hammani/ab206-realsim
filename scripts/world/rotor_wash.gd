extends Node3D
## Rotor-wash dust: when the helicopter is low, the downwash hits the ground and throws a ring of
## dust and grit outwards (plateau soil around Khouribga is dry and dusty). Strength grows as the
## rotor gets closer to the ground and with the induced (downwash) velocity, so a light skid-high
## hover raises a thick ring, a 15 m hover a thin one, and above about 2 rotor diameters nothing.
## Visual only (it does not change the flight model). Particle counts follow the graphics preset.

const DUST := Color(0.66, 0.57, 0.45)
const MAX_HUB_AGL := 22.0          # m; about two rotor diameters (rotor 10.16 m)
const AMOUNT := [120, 220, 340, 480] # Low, Medium, High, Ultra

var fdm
var terrain
var heli: Node3D
var ring: GPUParticles3D           # dust thrown outwards along the ground
var cloud: GPUParticles3D          # slower, bigger puffs that hang and drift
var strength := 0.0

func setup(p_fdm, p_terrain, p_heli: Node3D) -> void:
	fdm = p_fdm
	terrain = p_terrain
	heli = p_heli
	ring = _make(260, 1.6, Vector2(7.0, 13.0), Vector2(1.2, 3.2), 3.5, 7.0)
	cloud = _make(90, 3.2, Vector2(2.0, 4.5), Vector2(3.0, 9.0), 4.0, 9.0)
	add_child(ring)
	add_child(cloud)

func set_profile(preset: int) -> void:
	var n: int = AMOUNT[clampi(preset, 0, AMOUNT.size() - 1)]
	if ring:
		ring.amount = n
		cloud.amount = maxi(n / 3, 30)

func _make(n: int, life: float, speed: Vector2, size: Vector2, r_in: float, r_out: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = n
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, 30, 80))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	m.emission_ring_axis = Vector3.UP
	m.emission_ring_height = 0.4
	m.emission_ring_radius = r_out
	m.emission_ring_inner_radius = r_in
	m.direction = Vector3(0, 0.25, 0)
	m.spread = 25.0
	m.radial_velocity_min = speed.x
	m.radial_velocity_max = speed.y
	m.initial_velocity_min = 0.3
	m.initial_velocity_max = 1.5
	m.gravity = Vector3(0, 0.25, 0)        # warm dust rises a little
	m.damping_min = 1.5
	m.damping_max = 3.0
	m.scale_min = size.x
	m.scale_max = size.y
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.35))
	sc.add_point(Vector2(0.4, 0.8))
	sc.add_point(Vector2(1.0, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	m.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(DUST.r, DUST.g, DUST.b, 0.0))
	g.set_color(1, Color(DUST.r * 1.05, DUST.g * 1.05, DUST.b * 1.05, 0.0))
	g.add_point(0.1, Color(DUST.r, DUST.g, DUST.b, 0.75))
	g.add_point(0.55, Color(DUST.r, DUST.g, DUST.b, 0.45))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	m.angle_min = 0.0
	m.angle_max = 360.0
	p.process_material = m
	# soft round puff texture
	var rg := Gradient.new()
	rg.set_color(0, Color(1, 1, 1, 1))
	rg.set_color(1, Color(1, 1, 1, 0))
	rg.add_point(0.5, Color(1, 1, 1, 0.7))
	var tex := GradientTexture2D.new()
	tex.gradient = rg
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.disable_receive_shadows = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(3.0, 3.0)
	q.material = mat
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

## 0..1: how much dust the downwash raises now.
static func wash_strength(hub_agl: float, vi: float, nr_pct: float) -> float:
	if hub_agl > MAX_HUB_AGL or nr_pct < 50.0:
		return 0.0
	var h := 1.0 - smoothstep(4.0, MAX_HUB_AGL, hub_agl)     # strongest from skid height to ~4 m hub
	var v := clampf(vi / 9.0, 0.0, 1.2)                      # hover downwash ~9-10 m/s at 206 weights
	return clampf(h * v, 0.0, 1.0)

func _process(_dt: float) -> void:
	if fdm == null or heli == null:
		return
	strength = wash_strength(float(fdm.hub_agl), float(fdm.vi), float(fdm.nr_pct()))
	var on := strength > 0.04
	ring.emitting = on
	cloud.emitting = on and strength > 0.25
	if not on:
		return
	var hp := heli.global_position
	var gy: float = terrain.height_at(hp.x, hp.z) if terrain else hp.y - float(fdm.agl)
	global_position = Vector3(hp.x, gy + 0.3, hp.z)
	ring.amount_ratio = strength
	cloud.amount_ratio = clampf((strength - 0.25) * 1.4, 0.0, 1.0)
