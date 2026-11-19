extends RefCounted
## Real-map dressing for Khouribga (GMMK): runway, taxiways and aprons from OpenStreetMap,
## houses and trees placed from ESA WorldCover land cover. Data: data/maps/khouribga/map.json,
## produced by tools/maps/build_khouribga.py (see docs/MAPS.md for sources and accuracy).

var world            # world.gd
var terrain          # terrain.gd (real map loaded)
const TILE := 1024.0
## Draw distances per graphics preset (Low, Medium, High, Ultra), metres. 0 = no limit.
const RANGE_HOUSES := [2000.0, 3500.0, 7000.0, 11000.0]
const RANGE_TREES := [1500.0, 3000.0, 5000.0, 8000.0]
const RANGE_STREETS := [2500.0, 4000.0, 7000.0, 10000.0]
const RANGE_MAIN_ROADS := [5000.0, 9000.0, 0.0, 0.0]
var house_tiles: Array[GeometryInstance3D] = []
var tree_tiles: Array[GeometryInstance3D] = []
var street_tiles: Array[GeometryInstance3D] = []
var main_road_tiles: Array[GeometryInstance3D] = []
var area_tiles: Array[GeometryInstance3D] = []
var area_material: ShaderMaterial
var road_materials: Array[ShaderMaterial] = []

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
	var t0 := Time.get_ticks_msec()
	_roads(terrain.map_meta.get("roads", []))
	_areas(terrain.map_meta.get("areas", []))
	var t1 := Time.get_ticks_msec()
	_buildings(terrain.map_meta["buildings"])
	var t2 := Time.get_ticks_msec()
	_trees(terrain.map_meta["trees"])
	print("Khouribga map: roads %d ms, houses %d ms, trees %d ms" % [t1 - t0, t2 - t1, Time.get_ticks_msec() - t2])

static func _tile_key(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / TILE), floori(z / TILE))

static func _tile_centre(k: Vector2i) -> Vector3:
	return Vector3((k.x + 0.5) * TILE, 0.0, (k.y + 0.5) * TILE)

## Distance culling per preset: far houses, trees and streets are skipped (the photo shows them).
func set_draw_distance(preset: int) -> void:
	var p := clampi(preset, 0, RANGE_HOUSES.size() - 1)
	for t in house_tiles:
		t.visibility_range_end = RANGE_HOUSES[p]
	for t in tree_tiles:
		t.visibility_range_end = RANGE_TREES[p]
	for t in street_tiles:
		t.visibility_range_end = RANGE_STREETS[p]
	for t in main_road_tiles:
		t.visibility_range_end = RANGE_MAIN_ROADS[p]
	for t in area_tiles:
		t.visibility_range_end = RANGE_STREETS[p]

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
	var groups := {}
	for k in list.size():
		var b: Array = list[k]
		var key := _tile_key(float(b[0]), float(b[1]))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(b)
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/building.gdshader")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2552
	# Moroccan town colours: white and cream render, ochre, sand, a few salmon/pink walls
	var palette := [Color(0.80, 0.77, 0.70), Color(0.84, 0.83, 0.80), Color(0.76, 0.64, 0.50), Color(0.79, 0.70, 0.57), Color(0.74, 0.57, 0.48), Color(0.68, 0.58, 0.47)]
	# real landmarks (src 2..6): mosque hall, minaret, school/hospital/kiosk, industrial shed, fuel canopy
	var src_col := {2: Color(0.90, 0.89, 0.85), 3: Color(0.86, 0.80, 0.68), 4: Color(0.86, 0.80, 0.70), 5: Color(0.62, 0.63, 0.62), 6: Color(0.92, 0.92, 0.92)}
	var plain := {2: true, 3: true, 5: true, 6: true}
	for key in groups:
		var g: Array = groups[key]
		var c := _tile_centre(key)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = bm
		mm.instance_count = g.size()
		for k in g.size():
			var b: Array = g[k]
			var x := float(b[0])
			var z := float(b[1])
			var w := float(b[2])
			var d := float(b[3])
			var yaw := deg_to_rad(float(b[4]))
			var src := int(b[6]) if b.size() > 6 else 0
			var base := float(b[7]) if b.size() > 7 else 0.0
			var h := float(b[5]) + (0.0 if base > 0.0 else 0.6)
			var gnd := minf(minf(_gh(x - w * 0.4, z - d * 0.4), _gh(x + w * 0.4, z + d * 0.4)), _gh(x, z)) - 0.6
			if base > 0.0:
				gnd = _gh(x, z) + base
			var basis := Basis(Vector3.UP, PI * 0.5 - yaw).scaled(Vector3(w, h, d))
			mm.set_instance_transform(k, Transform3D(basis, Vector3(x - c.x, gnd + h * 0.5, z - c.z)))
			var col: Color = palette[rng.randi() % palette.size()].darkened(rng.randf() * 0.10)
			if src_col.has(src):
				col = (src_col[src] as Color).darkened(rng.randf() * 0.05)
			# negative height tells the shader to draw plain walls (no windows)
			mm.set_instance_custom_data(k, Color(col.r, col.g, col.b, -h if plain.has(src) else h))
			var ax := absf(cos(PI * 0.5 - yaw)) * w + absf(sin(PI * 0.5 - yaw)) * d
			var az := absf(sin(PI * 0.5 - yaw)) * w + absf(cos(PI * 0.5 - yaw)) * d
			terrain.add_building(Vector3(x, gnd, z), Vector3(ax, h, az))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.position = c
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(mi)
		house_tiles.append(mi)

## Real land use from OpenStreetMap: parks, sports pitches, cemeteries, school and hospital yards.
## Each area arrives as triangles (x, z pairs) already cut to a 10 m grid; vertices follow the ground.
## Pitches carry their rectangle (centre, direction, length, width) so the shader can draw the lines.
func _areas(list: Array) -> void:
	if list.is_empty():
		return
	area_material = ShaderMaterial.new()
	area_material.shader = load("res://shaders/area.gdshader")
	area_material.set_shader_parameter("photo", terrain.ortho)
	area_material.set_shader_parameter("map_size", terrain.SIZE)
	var groups := {}
	for a in list:
		var kind := int(a[0])
		var tri: Array = a[1]
		if tri.size() < 6:
			continue
		var key := _tile_key(float(tri[0]) * 0.5, float(tri[1]) * 0.5)
		if not groups.has(key):
			var st0 := SurfaceTool.new()
			st0.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[key] = st0
		var st: SurfaceTool = groups[key]
		var o := _tile_centre(key) * 2.0
		var rc := Vector2.ZERO
		var ru := Vector2(1, 0)
		var rl := 0.0
		var rw := 0.0
		if a.size() > 2:
			var r: Array = a[2]
			rc = Vector2(float(r[0]), float(r[1]))
			ru = Vector2(float(r[2]), float(r[3]))
			rl = float(r[4])
			rw = float(r[5])
		for k in range(0, tri.size() - 1, 2):
			var px := float(tri[k])
			var pz := float(tri[k + 1])
			var q := Vector2(px, pz) - rc
			st.set_uv(Vector2(q.dot(ru), q.dot(Vector2(-ru.y, ru.x))))
			st.set_uv2(Vector2(float(kind), rl * 1000.0 + rw))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(px - o.x, _gh(px, pz) + 0.22, pz - o.z))
	for key in groups:
		var mi := MeshInstance3D.new()
		mi.mesh = (groups[key] as SurfaceTool).commit()
		mi.material_override = area_material
		mi.position = _tile_centre(key) * 2.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(mi)
		area_tiles.append(mi)

## Season change: the areas tint the same satellite photo as the terrain.
func set_photo(t: Texture2D) -> void:
	if area_material:
		area_material.set_shader_parameter("photo", t)

## Roads and railways: draped strips, one mesh per 1 km tile and road type.
func _roads(list: Array) -> void:
	var groups := {}       # [tile, kind, major] -> SurfaceTool
	var mats := {}
	for r in list:
		var kind := int(r[0])
		var w := float(r[1])
		var pts_raw: Array = r[2]
		var major := w >= 7.0 or kind == 2
		var key := [_tile_key(float(pts_raw[0][0]) * 0.5, float(pts_raw[0][1]) * 0.5), kind, major]   # 2 km tiles
		if not groups.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[key] = st
		var pts: Array[Vector2] = []
		for p in pts_raw:
			pts.append(_v2(p))
		_strip(groups[key], pts, w, 0.05 + (0.01 if major else 0.0), _tile_centre(key[0]) * 2.0, 10.0)
	for key in groups:
		var kind: int = key[1]
		if not mats.has(kind):
			mats[kind] = _paved_material(3 + kind, 1.0, 1.0)
			road_materials.append(mats[kind])
		var mi := MeshInstance3D.new()
		mi.mesh = (groups[key] as SurfaceTool).commit()
		mi.material_override = mats[kind]
		mi.position = _tile_centre(key[0]) * 2.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(mi)
		if key[2]:
			main_road_tiles.append(mi)
		else:
			street_tiles.append(mi)

## Appends a strip of width w along pts (sampled every `step` m) to st, relative to origin o.
func _strip(st: SurfaceTool, pts: Array[Vector2], w: float, lift: float, o: Vector3, step: float) -> void:
	var dense: Array[Vector2] = []
	for k in pts.size() - 1:
		var seg := pts[k + 1] - pts[k]
		var n := maxi(1, int(ceil(seg.length() / step)))
		for s in n:
			dense.append(pts[k] + seg * (float(s) / n))
	dense.append(pts[pts.size() - 1])
	var along := 0.0
	var pl0 := Vector3.ZERO
	var pr0 := Vector3.ZERO
	var v0 := 0.0
	for k in dense.size():
		var d := Vector2.ZERO
		if k > 0:
			d += (dense[k] - dense[k - 1]).normalized()
		if k < dense.size() - 1:
			d += (dense[k + 1] - dense[k]).normalized()
		if d.length_squared() < 1e-6:
			continue
		d = d.normalized()
		var side := Vector2(-d.y, d.x) * (w * 0.5)
		if k > 0:
			along += dense[k].distance_to(dense[k - 1])
		var pl := dense[k] + side
		var pr := dense[k] - side
		var vl := Vector3(pl.x - o.x, _gh(pl.x, pl.y) + lift, pl.y - o.z)
		var vr := Vector3(pr.x - o.x, _gh(pr.x, pr.y) + lift, pr.y - o.z)
		if k > 0:
			# front faces point up (same order as the runway strips)
			for t in [[pl0, -w * 0.5, v0], [pr0, w * 0.5, v0], [vr, w * 0.5, along], [pl0, -w * 0.5, v0], [vr, w * 0.5, along], [vl, -w * 0.5, along]]:
				st.set_uv(Vector2(t[1], t[2]))
				st.set_uv2(Vector2(w, 0.0))
				st.set_normal(Vector3.UP)
				st.add_vertex(t[0])
		pl0 = vl
		pr0 = vr
		v0 = along

## Low-poly broadleaf tree (olive / eucalyptus look): trunk and three overlapping canopy lobes.
func _tree_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 6
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := Vector3(cos(a0) * 0.22, 0, sin(a0) * 0.22)
		var p1 := Vector3(cos(a1) * 0.22, 0, sin(a1) * 0.22)
		var t0 := Vector3(cos(a0) * 0.12, 3.0, sin(a0) * 0.12)
		var t1 := Vector3(cos(a1) * 0.12, 3.0, sin(a1) * 0.12)
		st.set_color(Color(0.38, 0.30, 0.21))
		for v in [p0, t1, p1, p0, t0, t1]:
			st.add_vertex(v)
	var lobes := [[Vector3(0, 4.6, 0), 2.4, Color(0.26, 0.33, 0.18)], [Vector3(1.0, 4.0, 0.5), 1.7, Color(0.22, 0.30, 0.15)], [Vector3(-0.8, 4.2, -0.7), 1.8, Color(0.29, 0.35, 0.20)]]
	for lb in lobes:
		var c: Vector3 = lb[0]
		var r: float = lb[1]
		var col: Color = lb[2]
		var rings := 4
		var segs := 8
		for ri in rings:
			var th0 := PI * ri / rings
			var th1 := PI * (ri + 1) / rings
			for si in segs:
				var ph0 := TAU * si / segs
				var ph1 := TAU * (si + 1) / segs
				var q := func(th: float, ph: float) -> Vector3:
					return c + Vector3(sin(th) * cos(ph) * r, cos(th) * r * 0.8, sin(th) * sin(ph) * r)
				var a: Vector3 = q.call(th0, ph0)
				var b2: Vector3 = q.call(th0, ph1)
				var cc: Vector3 = q.call(th1, ph0)
				var d: Vector3 = q.call(th1, ph1)
				var shade := 1.0 - 0.25 * float(ri) / rings
				st.set_color(col * shade)
				for v in [a, d, b2, a, cc, d]:
					st.add_vertex(v)
	st.generate_normals()
	return st.commit()

func _trees(list: Array) -> void:
	var groups := {}
	for t in list:
		var key := _tile_key(float(t[0]), float(t[1]))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(t)
	var mesh := _tree_mesh()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 778
	for key in groups:
		var g: Array = groups[key]
		var c := _tile_centre(key)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = g.size()
		for k in g.size():
			var t: Array = g[k]
			var s := float(t[2])
			var x := float(t[0])
			var z := float(t[1])
			mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.4), s)), Vector3(x - c.x, _gh(x, z) - 0.2, z - c.z)))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.position = c
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(mi)
		tree_tiles.append(mi)
