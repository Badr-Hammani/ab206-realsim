extends Node3D
## Builds the environment: sky, sun, fog, terrain, helipads, windsocks, trees, buildings.

const Terrain = preload("res://scripts/world/terrain.gd")
const Khouribga = preload("res://scripts/world/khouribga.gd")
const MAPS := {"valle": "Training valley (fictional)", "khouribga": "Khouribga GMMK (real terrain)"}

var terrain
var sun: DirectionalLight3D
var env: Environment
var trees: MultiMeshInstance3D
var windsocks: Array[Node3D] = []
var tree_capacity := 9000
var hover_spot := Vector3.ZERO       # lesson L3 hover-taxi target, 22 m north of the main pad centre
var map_id := "valle"
var season := "summer"
var real_map                         # khouribga.gd when a real map is loaded
var surface_lift := 0.0              # pad decks and painted marks raised above apron meshes on real maps

func build(id := "valle") -> void:
	map_id = id if MAPS.has(id) else "valle"
	_build_environment()
	terrain = Terrain.new()
	terrain.name = "Terrain"
	if map_id != "valle":
		terrain.map_dir = "res://data/maps/" + map_id
		terrain.season = season
	add_child(terrain)
	terrain.generate()
	if map_id != "valle":
		surface_lift = 0.1      # real maps draw apron/taxiway/runway meshes just above the ground
	for pad_name in terrain.pads:
		var pd: Dictionary = terrain.pads[pad_name]
		_build_pad(pd["pos"], pd["radius"], pad_name)
		if surface_lift > 0.0:
			# the pad deck sits on top of the apron: make the flight model's ground match it
			var deck := surface_lift + 0.03
			var half_side := minf(float(pd["radius"]) * 0.6, 12.0) * 1.4
			terrain.add_building(pd["pos"], Vector3(half_side, deck, half_side))
			pd["pos"] = pd["pos"] + Vector3(0, deck, 0)
	_build_training_marks()
	if map_id == "khouribga":
		env.fog_light_color = Color(0.74, 0.76, 0.78)   # dry plateau haze, slightly dusty
		var psm := env.sky.sky_material as ProceduralSkyMaterial
		psm.sky_top_color = Color(0.30, 0.50, 0.80)
		psm.sky_horizon_color = Color(0.74, 0.77, 0.80)
		psm.ground_horizon_color = Color(0.66, 0.60, 0.52)
		real_map = Khouribga.new()
		real_map.build(self)
	else:
		_build_buildings()
		_build_trees()

## Short place description for the instructor ("over the valley" / "over Khouribga").
func place_name() -> String:
	return "the Khouribga plateau" if map_id == "khouribga" else "the valley floor"

## Graphics preset 0-2: draw distances of houses, trees and streets on real maps.
func set_draw_preset(p: int) -> void:
	if real_map:
		real_map.set_draw_distance(p)

## Photo season of a real map ("spring" / "summer"); no reload needed.
func set_season(s: String) -> void:
	season = s
	if terrain:
		terrain.set_season(s)

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.32, 0.50, 0.78)
	psm.sky_horizon_color = Color(0.70, 0.77, 0.85)
	psm.ground_horizon_color = Color(0.55, 0.58, 0.58)
	psm.ground_bottom_color = Color(0.25, 0.27, 0.25)
	psm.sun_angle_max = 20.0
	sky.sky_material = psm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.75, 0.84)
	env.fog_density = 0.00012
	env.fog_sky_affect = 0.25
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 200.0
	add_child(sun)

## Visibility in metres (fog). 10 km ~ clear day; 1.5 km ~ marginal VFR.
func set_visibility(meters: float) -> void:
	env.fog_density = clampf(1.7 / maxf(meters, 300.0), 0.00005, 0.006)

func _pad_texture() -> ImageTexture:
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var c := Vector2(s * 0.5, s * 0.5)
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(c) / (s * 0.5)
			var g := 0.30 + 0.03 * sin(x * 0.9) * sin(y * 1.3)
			var col := Color(g, g, g * 0.98)
			if d > 0.86 and d < 0.95:
				col = Color(0.95, 0.80, 0.10)
			var lx := (x - c.x) / (s * 0.5)
			var ly := (y - c.y) / (s * 0.5)
			var in_h := absf(ly) < 0.42 and ((absf(lx + 0.26) < 0.06) or (absf(lx - 0.26) < 0.06) or (absf(ly) < 0.06 and absf(lx) < 0.26))
			if in_h:
				col = Color(0.97, 0.97, 0.97)
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _build_pad(p: Vector3, radius: float, pad_name: String) -> void:
	var pad := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = minf(radius * 0.6, 12.0)
	pm.bottom_radius = pm.top_radius
	pm.height = 0.06
	pm.radial_segments = 40
	pad.mesh = pm
	pad.position = p + Vector3(0, surface_lift, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _pad_texture()
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = false
	mat.uv1_scale = Vector3(0.5, 0.5, 0.5) / (pm.top_radius * 2.0) * 2.0
	mat.uv1_offset = Vector3(0.5, 0.5, 0.5)
	mat.roughness = 0.9
	pad.material_override = mat
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pad)
	# windsock next to each pad
	var ws := _make_windsock()
	var off := Vector3(pm.top_radius + 6.0, 0, -4.0)
	ws.position = Vector3(p.x + off.x, terrain.height_at(p.x + off.x, p.z + off.z), p.z + off.z)
	add_child(ws)
	windsocks.append(ws)
	# small marker posts around the pad edge for height and drift cues
	for k in 8:
		var a := TAU * (k + 0.5) / 8.0      # offset so the north hover-taxi line is clear
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.25, 0.6, 0.25)
		post.mesh = bm
		var q := p + Vector3(cos(a), 0, sin(a)) * (pm.top_radius + 2.0)
		post.position = Vector3(q.x, terrain.height_at(q.x, q.z) + 0.3, q.z)
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(1.0, 0.45, 0.05) if k % 2 == 0 else Color(0.95, 0.95, 0.95)
		post.material_override = pmat
		add_child(post)

## Painted training marks next to the main pad: a yellow hover-taxi line to the north and a
## yellow spot (ring + cross, 3 m) at its end. Flat ground, inside the flattened pad area.
func _build_training_marks() -> void:
	var p: Vector3 = terrain.pads["Main helipad"]["pos"]
	hover_spot = Vector3(p.x, terrain.height_at(p.x, p.z - 22.0), p.z - 22.0)
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color(0.98, 0.82, 0.10)
	yellow.roughness = 0.85
	var y0 := 0.035 + surface_lift
	# dashed line from the pad edge to the spot
	var z := p.z - 12.5
	while z > hover_spot.z + 2.0:
		var d := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.25, 0.02, 1.2)
		d.mesh = bm
		d.material_override = yellow
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		d.position = Vector3(p.x, terrain.height_at(p.x, z - 0.6) + y0, z - 0.6)
		add_child(d)
		z -= 2.0
	# ring + cross at the spot
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.3
	tm.outer_radius = 1.5
	tm.rings = 32
	tm.ring_segments = 4
	ring.mesh = tm
	ring.scale = Vector3(1.0, 0.05, 1.0)
	ring.material_override = yellow
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = hover_spot + Vector3(0, y0, 0)
	add_child(ring)
	for k in 2:
		var c := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(2.4, 0.02, 0.25) if k == 0 else Vector3(0.25, 0.02, 2.4)
		c.mesh = cb
		c.material_override = yellow
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.position = hover_spot + Vector3(0, y0, 0)
		add_child(c)

func _make_windsock() -> Node3D:
	var root := Node3D.new()
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.07
	cm.height = 5.0
	pole.mesh = cm
	pole.position = Vector3(0, 2.5, 0)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.85, 0.85, 0.85)
	pole.material_override = pmat
	root.add_child(pole)
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	pivot.position = Vector3(0, 4.9, 0)
	root.add_child(pivot)
	var sock := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.32
	sm.bottom_radius = 0.12
	sm.height = 2.4
	sock.mesh = sm
	sock.rotation_degrees = Vector3(90, 0, 0)  # cylinder along -Z/+Z
	sock.position = Vector3(0, 0, 1.2)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(1.0, 0.35, 0.05)
	sock.material_override = smat
	pivot.add_child(sock)
	return root

## Points each windsock downwind and droops it at low wind speed.
func update_windsocks(wind: Vector3) -> void:
	var hspd := Vector2(wind.x, wind.z).length()
	for ws in windsocks:
		var pv: Node3D = ws.get_node("Pivot")
		var droop := lerpf(75.0, 2.0, clampf(hspd / 7.7, 0.0, 1.0))   # full at 15 kt
		var yaw := atan2(wind.x, wind.z) if hspd > 0.2 else pv.rotation.y
		pv.rotation = Vector3(deg_to_rad(droop), yaw, 0.0)

func _box(pos: Vector3, size: Vector3, color: Color, collide := true) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos + Vector3(0, size.y * 0.5, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	mi.material_override = m
	add_child(mi)
	if collide:
		terrain.add_building(pos, size)

func _build_buildings() -> void:
	var p: Vector3 = terrain.pads["Main helipad"]["pos"]
	# hangar and small operations building near the main pad
	_box(p + Vector3(40, -0.3, 20), Vector3(22, 9, 18), Color(0.62, 0.64, 0.66))
	_box(p + Vector3(32, -0.3, -18), Vector3(8, 4, 6), Color(0.85, 0.82, 0.74))
	_box(p + Vector3(32, 3.7, -18), Vector3(2.5, 3, 2.5), Color(0.3, 0.32, 0.36))
	# fuel tank
	_box(p + Vector3(-30, -0.3, 22), Vector3(4, 3, 4), Color(0.8, 0.8, 0.2))
	# a hamlet along the valley floor
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for k in 14:
		var z := -600.0 - k * 55.0 + rng.randf_range(-15, 15)
		var x: float = terrain.valley_center_x(z) + rng.randf_range(80, 190) * (1 if k % 2 == 0 else -1)
		var h: float = terrain.height_at(x, z)
		_box(Vector3(x, h - 0.5, z), Vector3(rng.randf_range(7, 12), rng.randf_range(5, 8), rng.randf_range(7, 11)), Color(0.86, 0.80, 0.70).darkened(rng.randf() * 0.2))
	# church tower as a navigation landmark
	var tz := -1000.0
	var tx: float = terrain.valley_center_x(tz) + 140.0
	_box(Vector3(tx, terrain.height_at(tx, tz) - 0.5, tz), Vector3(5, 26, 5), Color(0.9, 0.88, 0.82))

func _tree_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 6
	# trunk
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var r := 0.25
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		var c := Color(0.35, 0.24, 0.14)
		st.set_color(c)
		st.set_normal(Vector3(cos(a0), 0, sin(a0)))
		st.add_vertex(p0)
		st.add_vertex(p1 + Vector3(0, 2.0, 0))
		st.add_vertex(p1)
		st.add_vertex(p0)
		st.add_vertex(p0 + Vector3(0, 2.0, 0))
		st.add_vertex(p1 + Vector3(0, 2.0, 0))
	# two cone tiers of foliage
	for tier in 2:
		var base_y := 1.6 + tier * 2.6
		var rr := 2.4 - tier * 0.7
		var top := Vector3(0, base_y + 4.2 - tier * 0.8, 0)
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var p0 := Vector3(cos(a0) * rr, base_y, sin(a0) * rr)
			var p1 := Vector3(cos(a1) * rr, base_y, sin(a1) * rr)
			st.set_color(Color(0.13, 0.27, 0.12).lightened(tier * 0.06))
			st.set_normal((Vector3(cos(a0), 0.6, sin(a0))).normalized())
			st.add_vertex(p0)
			st.add_vertex(top)
			st.add_vertex(p1)
	st.generate_normals()
	return st.commit()

func _build_trees() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _tree_mesh()
	var xforms: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 1206
	var placed := 0
	var tries := 0
	while xforms.size() < tree_capacity and tries < tree_capacity * 6:
		tries += 1
		var x := rng.randf_range(-1900, 1900)
		var z := rng.randf_range(-1900, 1900)
		var h: float = terrain.height_at(x, z)
		if h > 1050.0:
			continue
		var n: Vector3 = terrain.normal_at(x, z)
		if n.y < 0.86:
			continue
		var ok := true
		for pad_name in terrain.pads:
			var pp: Vector3 = terrain.pads[pad_name]["pos"]
			if Vector2(x - pp.x, z - pp.z).length() < float(terrain.pads[pad_name]["radius"]) + 25.0:
				ok = false
		for b in terrain.buildings:
			var mn: Vector3 = b["min"]
			var mx: Vector3 = b["max"]
			if x > mn.x - 6 and x < mx.x + 6 and z > mn.z - 6 and z < mx.z + 6:
				ok = false
		if not ok:
			continue
		# clusters: skip some by low-frequency pattern so forests and meadows alternate
		if sin(x * 0.004 + 1.3) * cos(z * 0.0037) + rng.randf_range(-0.6, 0.6) < 0.05:
			continue
		var s := rng.randf_range(0.75, 1.35)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.25), s)), Vector3(x, h - 0.2, z))
		xforms.append(t)
	placed = xforms.size()
	mm.instance_count = placed
	for k in placed:
		mm.set_instance_transform(k, xforms[k])
	trees = MultiMeshInstance3D.new()
	trees.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	trees.material_override = mat
	trees.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trees)

func set_tree_count(n: int) -> void:
	if trees:
		trees.multimesh.visible_instance_count = mini(n, trees.multimesh.instance_count)
