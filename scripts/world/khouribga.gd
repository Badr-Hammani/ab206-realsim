extends RefCounted
## Real-map dressing for Khouribga (GMMK): runway, taxiways and aprons from OpenStreetMap,
## houses and trees placed from ESA WorldCover land cover. Data: data/maps/khouribga/map.json,
## produced by tools/maps/build_khouribga.py (see docs/MAPS.md for sources and accuracy).

var world            # world.gd
var terrain          # terrain.gd (real map loaded)
var buildings: MultiMeshInstance3D
var building_total := 0

func build(w) -> void:
	world = w
	terrain = w.terrain
	var a: Dictionary = terrain.map_meta["airport"]
	var rw: Dictionary = a["runway"]
	var e0 := _v2(rw["ends"][0])
	var e1 := _v2(rw["ends"][1])
	for ap in a["aprons"]:
		_apron(ap)
	var tw_w := float(a["taxiway_width"])
	for t in a["taxiways"]:
		var pts: Array[Vector2] = []
		for p in t:
			pts.append(_v2(p))
		_ribbon(pts, tw_w, 1, 0.11)
	_ribbon([e0, e1] as Array[Vector2], float(rw["width"]), 0, 0.16)
	var hdg := float(rw["true_heading"])
	var des: Array = rw["designators"]
	var dir := (e1 - e0).normalized()
	_runway_number(str(des[0]), e0 + dir * 55.0, hdg)
	_runway_number(str(des[1]), e1 - dir * 55.0, hdg + 180.0)
	# windsock beside the touchdown zone of runway 05, 70 m left of the centreline
	var side := Vector2(-dir.y, dir.x)
	for wp in [e0 + dir * 320.0 + side * 70.0, e1 - dir * 320.0 - side * 70.0]:
		var ws: Node3D = world._make_windsock()
		ws.position = Vector3(wp.x, terrain.height_at(wp.x, wp.y), wp.y)
		world.add_child(ws)
		world.windsocks.append(ws)
	_buildings(terrain.map_meta["buildings"])
	_trees(terrain.map_meta["trees"])

func _v2(p) -> Vector2:
	return Vector2(float(p[0]), float(p[1]))

func _gh(x: float, z: float) -> float:
	return terrain._grid_height(x, z)

func _paved_material(kind: int, length_m: float, width_m: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/paved.gdshader")
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("length_m", length_m)
	m.set_shader_parameter("width_m", width_m)
	if kind == 2:
		m.set_shader_parameter("asphalt", Vector3(0.30, 0.29, 0.27))   # concrete apron
	return m

## Strip of width w along a polyline, draped on the terrain every ~6 m.
func _ribbon(pts: Array[Vector2], w: float, kind: int, lift: float) -> void:
	var dense: Array[Vector2] = []
	for k in pts.size() - 1:
		var seg := pts[k + 1] - pts[k]
		var n := maxi(1, int(ceil(seg.length() / 6.0)))
		for s in n:
			dense.append(pts[k] + seg * (float(s) / n))
	dense.append(pts[pts.size() - 1])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_v := 0.0
	for k in dense.size():
		var d := Vector2.ZERO
		if k > 0:
			d += (dense[k] - dense[k - 1]).normalized()
		if k < dense.size() - 1:
			d += (dense[k + 1] - dense[k]).normalized()
		d = d.normalized()
		var side := Vector2(-d.y, d.x) * (w * 0.5)
		if k > 0:
			along += dense[k].distance_to(dense[k - 1])
		var pl := dense[k] + side
		var pr := dense[k] - side
		var vl := Vector3(pl.x, _gh(pl.x, pl.y) + lift, pl.y)
		var vr := Vector3(pr.x, _gh(pr.x, pr.y) + lift, pr.y)
		if k > 0:
			for t in [[prev_l, -w * 0.5, prev_v], [prev_r, w * 0.5, prev_v], [vr, w * 0.5, along], [prev_l, -w * 0.5, prev_v], [vr, w * 0.5, along], [vl, -w * 0.5, along]]:
				st.set_uv(Vector2(t[1], t[2]))
				st.set_normal(Vector3.UP)
				st.add_vertex(t[0])
		prev_l = vl
		prev_r = vr
		prev_v = along
	var mi := MeshInstance3D.new()
	st.generate_normals()
	mi.mesh = st.commit()
	# winding: make sure the faces point up (Godot culls back faces)
	mi.material_override = _paved_material(kind, along, w)
	(mi.material_override as ShaderMaterial).render_priority = kind
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	_fix_winding(mi)

## Flips the triangles if the generated normals point down (cheap check on the first face).
func _fix_winding(mi: MeshInstance3D) -> void:
	var arr := mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	if v.size() < 3:
		return
	var n := (v[1] - v[0]).cross(v[2] - v[0])
	# Godot front faces are clockwise seen from the front: their geometric normal (b-a)x(c-a) points away from the viewer
	if n.y > 0.0:
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for k in range(0, v.size(), 3):
			var t := v[k + 1]
			v[k + 1] = v[k + 2]
			v[k + 2] = t
			var tu := uv[k + 1]
			uv[k + 1] = uv[k + 2]
			uv[k + 2] = tu
		for k in nn.size():
			nn[k] = Vector3.UP
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_NORMAL] = nn
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat = mi.material_override
		mi.mesh = m
		mi.material_override = mat
	else:
		var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for k in nn.size():
			nn[k] = Vector3.UP
		arr[Mesh.ARRAY_NORMAL] = nn
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mi.mesh = m

func _apron(ring: Array) -> void:
	var poly := PackedVector2Array()
	for k in ring.size() - 1:       # last point repeats the first
		poly.append(_v2(ring[k]))
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in idx:
		var p := poly[k]
		st.set_uv(Vector2(0.0, 0.0))
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(p.x, _gh(p.x, p.y) + 0.07, p.y))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _paved_material(2, 1.0, 1.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	_fix_winding(mi)

## Runway designator painted on the surface (Label3D lying flat, top of the digits toward the far end).
func _runway_number(txt: String, p: Vector2, hdg_deg: float) -> void:
	var l := Label3D.new()
	l.text = txt
	l.font_size = 256
	l.pixel_size = 0.045
	l.outline_size = 0
	l.modulate = Color(0.93, 0.93, 0.91)
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.rotation = Vector3(-PI * 0.5, -deg_to_rad(hdg_deg), 0.0)
	l.position = Vector3(p.x, _gh(p.x, p.y) + 0.22, p.y)
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(l)

func _buildings(list: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	mm.mesh = bm
	mm.instance_count = list.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2552
	var palette := [Color(0.87, 0.82, 0.72), Color(0.92, 0.89, 0.83), Color(0.80, 0.68, 0.55), Color(0.86, 0.76, 0.62), Color(0.95, 0.94, 0.91), Color(0.74, 0.62, 0.50)]
	for k in list.size():
		var b: Array = list[k]
		var x := float(b[0])
		var z := float(b[1])
		var w := float(b[2])
		var d := float(b[3])
		var yaw := deg_to_rad(float(b[4]))
		var h := float(b[5]) + 0.6
		var g := minf(minf(_gh(x - w * 0.4, z - d * 0.4), _gh(x + w * 0.4, z + d * 0.4)), _gh(x, z)) - 0.6
		var basis := Basis(Vector3.UP, PI * 0.5 - yaw).scaled(Vector3(w, h, d))
		mm.set_instance_transform(k, Transform3D(basis, Vector3(x, g + h * 0.5, z)))
		mm.set_instance_color(k, palette[rng.randi() % palette.size()].darkened(rng.randf() * 0.12))
		var ax := absf(cos(PI * 0.5 - yaw)) * w + absf(sin(PI * 0.5 - yaw)) * d
		var az := absf(sin(PI * 0.5 - yaw)) * w + absf(cos(PI * 0.5 - yaw)) * d
		terrain.add_building(Vector3(x, g, z), Vector3(ax, h, az))
	buildings = MultiMeshInstance3D.new()
	buildings.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	buildings.material_override = mat
	buildings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(buildings)
	building_total = list.size()

## Share of the (randomly ordered) estimated houses drawn; real OSM buildings come first and always show.
func set_building_share(f: float) -> void:
	if buildings:
		buildings.multimesh.visible_instance_count = int(building_total * clampf(f, 0.05, 1.0))

func _tree_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 6
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var r := 0.22
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		st.set_color(Color(0.40, 0.32, 0.22))
		for v in [p0, p1 + Vector3(0, 2.6, 0), p1, p0, p0 + Vector3(0, 2.6, 0), p1 + Vector3(0, 2.6, 0)]:
			st.add_vertex(v)
	# round canopy (olive / eucalyptus look): two rings of a low-poly ball
	var c := Vector3(0, 4.3, 0)
	var rr := 2.6
	var top := c + Vector3(0, 2.2, 0)
	var bot := c + Vector3(0, -1.6, 0)
	for i in 8:
		var a0 := TAU * i / 8.0
		var a1 := TAU * (i + 1) / 8.0
		var q0 := c + Vector3(cos(a0) * rr, 0, sin(a0) * rr)
		var q1 := c + Vector3(cos(a1) * rr, 0, sin(a1) * rr)
		st.set_color(Color(0.24, 0.31, 0.17))
		for v in [q0, top, q1]:
			st.add_vertex(v)
		st.set_color(Color(0.19, 0.25, 0.13))
		for v in [q0, q1, bot]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()

func _trees(list: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _tree_mesh()
	mm.instance_count = list.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 778
	for k in list.size():
		var t: Array = list[k]
		var s := float(t[2])
		var x := float(t[0])
		var z := float(t[1])
		mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.3), s)), Vector3(x, _gh(x, z) - 0.2, z)))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	world.trees = mi
	world.tree_capacity = list.size()
