extends Node3D
## Visual model of the Bell 206B-3 built from primitives (placeholder art for M1).
## Everything that moves here is driven by the flight model state:
## rotor speed and disc tilt (flapping), tail rotor, cyclic stick, collective lever,
## throttle twist grip and pedals.

var hub_tilt: Node3D
var hub_spin: Node3D
var disc: MeshInstance3D
var disc_mat: StandardMaterial3D
var blade_mat: StandardMaterial3D
var tail_spin: Node3D
var cyclic_pivot: Node3D
var collective_pivot: Node3D
var twist_grip: Node3D
var pedal_l: Node3D
var pedal_r: Node3D
var panel_quad: MeshInstance3D
var panel_back: MeshInstance3D
var interior: Node3D
var exterior_glass: MeshInstance3D
var lower_body: MeshInstance3D
var stripe_body: MeshInstance3D
var hub_h := 1.65
var mast_tilt := 0.087

func _mat(c: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mesh(parent, b, pos, mat, rot)

func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, rot := Vector3.ZERO, seg := 12) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return _mesh(parent, c, pos, mat, rot)

func build(fdm, panel_texture: Texture2D) -> void:
	hub_h = fdm.hub_h
	mast_tilt = fdm.mast_tilt
	var white := _mat(Color(0.93, 0.93, 0.90), 0.45)
	var stripe := _mat(Color(0.10, 0.22, 0.48), 0.5)
	var dark := _mat(Color(0.12, 0.12, 0.13), 0.7)
	var metal := _mat(Color(0.55, 0.56, 0.58), 0.4, 0.6)
	var glass := _mat(Color(0.25, 0.35, 0.42, 0.35), 0.05)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var ext := Node3D.new()
	ext.name = "Exterior"
	add_child(ext)
	# cabin glass and lower fuselage
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 24
	sph.rings = 12
	exterior_glass = _mesh(ext, sph, Vector3(0, 0.18, -0.85), glass, Vector3.ZERO, Vector3(0.70, 0.78, 1.62))
	lower_body = _mesh(ext, sph, Vector3(0, -0.22, -0.55), white, Vector3.ZERO, Vector3(0.72, 0.42, 1.75))
	stripe_body = _mesh(ext, sph, Vector3(0, -0.12, -0.55), stripe, Vector3.ZERO, Vector3(0.725, 0.08, 1.70))
	# aft cabin / engine and transmission fairings
	_box(ext, Vector3(1.3, 1.1, 1.3), Vector3(0, 0.12, 0.65), white)
	_box(ext, Vector3(0.85, 0.5, 1.9), Vector3(0, 0.92, 0.55), white)
	_cyl(ext, 0.16, 0.16, 0.5, Vector3(0, 1.05, 1.65), dark, Vector3(90, 0, 0))   # exhaust
	# tail boom, fins, stabilizer
	_cyl(ext, 0.13, 0.32, 5.1, Vector3(0, 0.55, 3.75), white, Vector3(90, 0, 0), 14)
	_box(ext, Vector3(0.06, 1.25, 0.65), Vector3(0, 1.05, 6.05), white, Vector3(-25, 0, 0))
	_box(ext, Vector3(0.06, 0.55, 0.45), Vector3(0, 0.15, 6.05), white, Vector3(30, 0, 0))
	_box(ext, Vector3(2.0, 0.05, 0.45), Vector3(0, 0.55, 4.6), white)
	_box(ext, Vector3(0.05, 0.25, 0.45), Vector3(1.0, 0.62, 4.6), stripe)
	_box(ext, Vector3(0.05, 0.25, 0.45), Vector3(-1.0, 0.62, 4.6), stripe)
	# skids (bottom at -cg_height)
	var ys: float = -fdm.cg_height + 0.04
	for sx in [-1.0, 1.0]:
		_cyl(ext, 0.04, 0.04, 2.9, Vector3(sx * 0.95, ys, -0.05), metal, Vector3(90, 0, 0))
		_cyl(ext, 0.04, 0.04, 0.5, Vector3(sx * 0.95, ys + 0.12, -1.6), metal, Vector3(-60, 0, 0))
	for cz in [-0.75, 0.8]:
		_cyl(ext, 0.045, 0.045, 1.9, Vector3(0, ys + 0.5, cz), metal, Vector3(0, 0, 90))
		for sx in [-1.0, 1.0]:
			_cyl(ext, 0.045, 0.045, 0.62, Vector3(sx * 0.86, ys + 0.24, cz), metal, Vector3(0, 0, sx * -18.0))
	# mast and main rotor
	_cyl(ext, 0.07, 0.09, 0.6, Vector3(0, hub_h - 0.3, 0), metal)
	hub_tilt = Node3D.new()
	hub_tilt.position = Vector3(0, hub_h, 0)
	add_child(hub_tilt)
	hub_spin = Node3D.new()
	hub_tilt.add_child(hub_spin)
	blade_mat = _mat(Color(0.14, 0.14, 0.15), 0.5)
	_box(hub_spin, Vector3(0.5, 0.12, 0.25), Vector3.ZERO, metal)
	for s in [-1.0, 1.0]:
		_box(hub_spin, Vector3(4.85, 0.035, 0.33), Vector3(s * 2.62, 0.0, 0.0), blade_mat)
		_box(hub_spin, Vector3(0.25, 0.04, 0.34), Vector3(s * 4.95, 0.0, 0.0), _mat(Color(0.95, 0.85, 0.1)))
	var dm := CylinderMesh.new()
	dm.top_radius = 5.08
	dm.bottom_radius = 5.08
	dm.height = 0.01
	dm.radial_segments = 48
	disc_mat = _mat(Color(0.1, 0.1, 0.1, 0.18), 1.0)
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	disc = _mesh(hub_tilt, dm, Vector3.ZERO, disc_mat)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# tail rotor on the left side of the tail
	var tr_hub := Node3D.new()
	tr_hub.position = Vector3(-0.2, 0.92, 6.0)
	add_child(tr_hub)
	tail_spin = Node3D.new()
	tr_hub.add_child(tail_spin)
	for s in [-1.0, 1.0]:
		_box(tail_spin, Vector3(0.02, 0.78, 0.12), Vector3(0, s * 0.42, 0), blade_mat)

	_build_interior(fdm, panel_texture)

func _build_interior(fdm, panel_texture: Texture2D) -> void:
	interior = Node3D.new()
	interior.name = "Interior"
	add_child(interior)
	var grey := _mat(Color(0.20, 0.21, 0.22), 0.8)
	var black := _mat(Color(0.05, 0.05, 0.05), 0.6)
	var seat := _mat(Color(0.30, 0.24, 0.18), 0.9)
	var frame := _mat(Color(0.32, 0.33, 0.34), 0.7)
	# floor, seats, centre console
	_box(interior, Vector3(1.3, 0.04, 1.7), Vector3(0, -0.47, -1.1), grey)
	for sx in [-0.38, 0.38]:
		_box(interior, Vector3(0.5, 0.12, 0.5), Vector3(sx, -0.2, -0.75), seat)
		_box(interior, Vector3(0.5, 0.7, 0.1), Vector3(sx, 0.18, -0.48), seat)
	# instrument panel and glareshield (pilot sits right seat, panel centred)
	panel_back = _box(interior, Vector3(1.15, 0.5, 0.06), Vector3(0.0, 0.0, -2.0), black, Vector3(-18, 0, 0))
	_box(interior, Vector3(1.2, 0.04, 0.14), Vector3(0.0, 0.25, -2.02), black)
	var qm := QuadMesh.new()
	qm.size = Vector2(1.05, 0.44)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_texture = panel_texture
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	panel_quad = _mesh(interior, qm, Vector3(0.0, 0.0, -1.965), pmat, Vector3(-18, 0, 0))
	_box(interior, Vector3(0.22, 0.4, 0.5), Vector3(0.0, -0.3, -1.65), black, Vector3(-30, 0, 0))
	# canopy frame. Real 206B-3: two curved windshield panes split by one slim centre
	# post that runs from the top of the instrument console up and AFT to the roof,
	# plus the forward door posts out at the sides where the windshield wraps round.
	# All posts lean back at the top (rotation x positive tips +Y towards +Z = aft).
	# Dark matte paint, like the real cabin interior, so they read as frame, not bars.
	var post := _mat(Color(0.09, 0.09, 0.10), 0.9)
	# centre post: glareshield (y 0.27, z -2.05) up to the roof header (y 1.00, z -1.70)
	_box(interior, Vector3(0.022, 0.81, 0.03), Vector3(0.0, 0.635, -1.875), post, Vector3(25.6, 0, 0))
	# windshield header along the front edge of the roof
	_box(interior, Vector3(1.22, 0.05, 0.06), Vector3(0.0, 0.96, -1.70), post)
	for sx in [-1.0, 1.0]:
		# forward door post, out at the side where the windshield wraps round:
		# from beside the pedals (y -0.10, z -1.55) up and aft to the roof (y 0.95, z -1.25)
		_box(interior, Vector3(0.025, 1.09, 0.03), Vector3(sx * 0.64, 0.425, -1.40), post, Vector3(16, 0, 0))
		_box(interior, Vector3(0.04, 0.05, 0.47), Vector3(sx * 0.63, 0.955, -1.475), post)   # roof side rail
		_box(interior, Vector3(0.035, 1.25, 0.04), Vector3(sx * 0.70, 0.35, -0.42), frame)   # aft door post
		_box(interior, Vector3(0.03, 0.3, 1.1), Vector3(sx * 0.714, -0.32, -1.0), frame)   # lower door
	_box(interior, Vector3(1.2, 0.04, 1.35), Vector3(0, 0.98, -1.025), grey)      # roof
	_box(interior, Vector3(0.5, 0.08, 0.3), Vector3(0.0, 0.9, -1.3), black)       # overhead console
	# cyclic stick (right seat pilot, between knees)
	cyclic_pivot = Node3D.new()
	cyclic_pivot.position = Vector3(0.38, -0.45, -1.25)
	interior.add_child(cyclic_pivot)
	_cyl(cyclic_pivot, 0.016, 0.022, 0.62, Vector3(0, 0.31, 0), black)
	_cyl(cyclic_pivot, 0.03, 0.03, 0.12, Vector3(0, 0.64, 0.0), _mat(Color(0.15, 0.15, 0.15), 0.9))
	# collective lever at the pilot's left hand
	collective_pivot = Node3D.new()
	collective_pivot.position = Vector3(0.11, -0.38, -0.62)
	interior.add_child(collective_pivot)
	_cyl(collective_pivot, 0.018, 0.022, 0.62, Vector3(0, 0, -0.31), black, Vector3(90, 0, 0))
	twist_grip = Node3D.new()
	twist_grip.position = Vector3(0, 0, -0.6)
	collective_pivot.add_child(twist_grip)
	_cyl(twist_grip, 0.03, 0.03, 0.14, Vector3.ZERO, _mat(Color(0.12, 0.12, 0.12), 0.9), Vector3(90, 0, 0))
	_box(twist_grip, Vector3(0.012, 0.012, 0.13), Vector3(0, 0.03, 0), _mat(Color(0.95, 0.95, 0.95)))  # index mark
	# pedals
	pedal_l = Node3D.new()
	pedal_r = Node3D.new()
	pedal_l.position = Vector3(0.24, -0.42, -1.75)
	pedal_r.position = Vector3(0.52, -0.42, -1.75)
	interior.add_child(pedal_l)
	interior.add_child(pedal_r)
	for pn in [pedal_l, pedal_r]:
		_box(pn, Vector3(0.1, 0.18, 0.03), Vector3.ZERO, _mat(Color(0.3, 0.3, 0.3), 0.5, 0.5), Vector3(-30, 0, 0))

func set_cockpit_view(on: bool, panel_2d_shown := false) -> void:
	interior.visible = true
	# only one instrument panel at a time: when the 2D copy (Tab) is on screen,
	# the 3D panel face is hidden so the two never overlap.
	panel_quad.visible = not (on and panel_2d_shown)
	panel_back.visible = panel_quad.visible
	exterior_glass.visible = not on
	lower_body.visible = not on
	stripe_body.visible = not on

func update_visual(fdm, dt: float) -> void:
	var nr_frac: float = fdm.nr / fdm.omega100
	hub_spin.rotation.y = fmod(hub_spin.rotation.y + fdm.nr * dt, TAU)
	hub_tilt.rotation = Vector3(-(fdm.mast_tilt - fdm.a1), 0.0, -fdm.b1)
	disc_mat.albedo_color.a = clampf((nr_frac - 0.25) * 0.3, 0.0, 0.2)
	tail_spin.rotation.x = fmod(tail_spin.rotation.x + fdm.nr * fdm.tr_gear * dt, TAU)
	cyclic_pivot.rotation = Vector3(-fdm.cyclic_lon * deg_to_rad(14.0), 0.0, -fdm.cyclic_lat * deg_to_rad(12.0))
	collective_pivot.rotation = Vector3(fdm.collective * deg_to_rad(22.0), 0.0, 0.0)
	twist_grip.rotation = Vector3(0.0, 0.0, fdm.throttle * deg_to_rad(75.0))
	pedal_l.position.z = -1.75 - (-fdm.pedal) * 0.07
	pedal_r.position.z = -1.75 - fdm.pedal * 0.07
