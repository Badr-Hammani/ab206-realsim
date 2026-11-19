extends Node3D
## Terrain height grid. Two sources:
##  - procedural 4 x 4 km test valley ("Valle Bianca", fictional, realistic elevations 280-1300 m MSL)
##  - a real map loaded from data/maps/<id>/ (heights from a DEM + satellite photo), see load_map().
## The same height grid is used for rendering AND for the flight model's skid contact,
## ground effect and AGL, so what you see is what you hit.

var SIZE := 4096.0
var N := 257                   # vertices per side (16 m spacing)
var CELL := SIZE / float(N - 1)
var HALF := SIZE * 0.5
var map_dir := ""              # "" = procedural valley, else e.g. "res://data/maps/khouribga"
var map_meta := {}             # map.json of a real map
var ortho: ImageTexture        # satellite photo of a real map
var season := "summer"         # which photo of a real map: "spring" (green fields) or "summer" (dry)
var photo_material: ShaderMaterial
var tiles: Array[MeshInstance3D] = []
const BUCKET := 64.0           # building lookup grid (m)
var _bld_grid := {}            # Vector2i -> Array of building indices

var heights := PackedFloat32Array()
var buildings: Array = []      # each: {"min": Vector3, "max": Vector3}
var pads := {}                 # name -> {"pos": Vector3, "radius": float, "heading": float}
var mesh_instance: MeshInstance3D

var _n_large := FastNoiseLite.new()
var _n_ridge := FastNoiseLite.new()
var _n_detail := FastNoiseLite.new()

func _init() -> void:
	_n_large.seed = 206
	_n_large.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_large.frequency = 1.0 / 1400.0
	_n_large.fractal_octaves = 4
	_n_ridge.seed = 3
	_n_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_n_ridge.frequency = 1.0 / 900.0
	_n_ridge.fractal_octaves = 5
	_n_detail.seed = 77
	_n_detail.frequency = 1.0 / 120.0
	_n_detail.fractal_octaves = 3

static func valley_center_x(z: float) -> float:
	return 260.0 * sin(z / 700.0)

func _raw_height(x: float, z: float) -> float:
	var d := absf(x - valley_center_x(z))
	var floor_h := 280.0 + 18.0 * _n_large.get_noise_2d(x, z) + 4.0 * _n_detail.get_noise_2d(x, z)
	var m := smoothstep(220.0, 1500.0, d)
	var mountain := m * (520.0 + 260.0 * _n_large.get_noise_2d(x * 1.7 + 500.0, z * 1.7)) + m * m * 260.0 * _n_ridge.get_noise_2d(x, z)
	var edge := smoothstep(1450.0, 2048.0, maxf(absf(x), absf(z))) * 420.0
	return floor_h + mountain + edge

## Loads a real map: height.bin (uint16 * height_scale m, row = z index from north), map.json, photo.
func load_map(dir: String) -> bool:
	var js := FileAccess.get_file_as_string(dir + "/map.json")
	var meta = JSON.parse_string(js)
	if typeof(meta) != TYPE_DICTIONARY:
		push_error("map.json missing in " + dir)
		return false
	map_meta = meta
	map_dir = dir
	SIZE = float(meta["size_m"])
	N = int(meta["n"])
	CELL = SIZE / float(N - 1)
	HALF = SIZE * 0.5
	var raw := FileAccess.get_file_as_bytes(dir + "/height.bin")
	var sc := float(meta["height_scale"])
	heights.resize(N * N)
	for k in N * N:
		heights[k] = raw.decode_u16(k * 2) * sc
	ortho = _load_photo(season)
	var pd: Dictionary = meta["pads"]
	for pad_name in pd:
		var a: Array = pd[pad_name]
		_add_pad(pad_name, Vector3(a[0], 0.0, a[1]), a[2], 30.0 if a[2] > 12.0 else 18.0, 0.0)
	_build_tiled_mesh()
	return true

func _load_photo(s: String) -> ImageTexture:
	var photos: Dictionary = map_meta.get("photos", {})
	var f: String = photos.get(s, photos.values()[0] if photos.size() > 0 else "")
	var img := Image.new()
	if f == "" or img.load_jpg_from_buffer(FileAccess.get_file_as_bytes(map_dir + "/" + f)) != OK:
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Swap the satellite photo (real maps only) without reloading.
func set_season(s: String) -> void:
	season = s
	if map_dir == "" or photo_material == null:
		return
	var t := _load_photo(s)
	if t:
		ortho = t
		photo_material.set_shader_parameter("photo", t)

## Draw distances (m) of the three terrain detail levels: 16 m grid near, 32 m, 64 m far.
## Ranges are measured to the 2 km tile centre, so the near level must reach past ~1.45 km.
const LOD_RANGES := [2000.0, 5000.0]
const LOD_RANGES_PRESET := [[1500.0, 4000.0], [2000.0, 5000.0], [2500.0, 6500.0]]

## Terrain detail levels per graphics preset (0 Low, 1 Medium, 2 High).
func set_lod_preset(p: int) -> void:
	var r: Array = LOD_RANGES_PRESET[clampi(p, 0, 2)]
	for k in tiles.size():
		var li := k % 3
		var mi := tiles[k]
		mi.visibility_range_begin = 0.0 if li == 0 else float(r[li - 1])
		mi.visibility_range_end = float(r[li]) if li < 2 else 0.0

## Real maps: the grid is cut into 2 km tiles, each with three detail levels that Godot swaps
## by distance (visibility ranges). Skirts hide the small cracks where two levels meet.
func _build_tiled_mesh() -> void:
	var norms := PackedVector3Array()
	norms.resize(N * N)
	for j in N:
		var jd := maxi(j - 1, 0)
		var ju := mini(j + 1, N - 1)
		for i in N:
			var il := maxi(i - 1, 0)
			var ir := mini(i + 1, N - 1)
			var hx := heights[j * N + ir] - heights[j * N + il]
			var hz := heights[ju * N + i] - heights[jd * N + i]
			norms[j * N + i] = Vector3(-hx / ((ir - il) * CELL), 1.0, -hz / ((ju - jd) * CELL)).normalized()
	photo_material = ShaderMaterial.new()
	photo_material.shader = load("res://shaders/terrain_photo.gdshader")
	photo_material.set_shader_parameter("photo", ortho)
	photo_material.set_shader_parameter("map_size", SIZE)
	var T := 128
	var nt := (N - 1) / T
	for ty in nt:
		for tx in nt:
			var lods := [1, 2, 4]
			for li in lods.size():
				var mi := _tile_mesh(tx * T, ty * T, T, lods[li], norms)
				mi.visibility_range_begin = 0.0 if li == 0 else LOD_RANGES[li - 1]
				mi.visibility_range_end = LOD_RANGES[li] if li < 2 else 0.0
				mi.material_override = photo_material
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mi)
				tiles.append(mi)
	mesh_instance = tiles[0]
	_build_far_plane()

func _tile_mesh(i0: int, j0: int, T: int, step: int, norms: PackedVector3Array) -> MeshInstance3D:
	var n := T / step + 1
	var cx := -HALF + (i0 + T * 0.5) * CELL
	var cz := -HALF + (j0 + T * 0.5) * CELL
	var verts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize(n * n)
	nrm.resize(n * n)
	for b in n:
		var j := j0 + b * step
		for a in n:
			var i := i0 + a * step
			verts[b * n + a] = Vector3(-HALF + i * CELL - cx, heights[j * N + i], -HALF + j * CELL - cz)
			nrm[b * n + a] = norms[j * N + i]
	for b in n - 1:
		for a in n - 1:
			var p := b * n + a
			idx.append_array([p, p + 1, p + n + 1, p, p + n + 1, p + n])
	# skirts: hang each border 6 m down so a coarser neighbour never shows a gap
	var border: Array[int] = []
	for a in n:
		border.append(a)
	for b in range(1, n):
		border.append(b * n + n - 1)
	for a in range(n - 2, -1, -1):
		border.append((n - 1) * n + a)
	for b in range(n - 2, -1, -1):
		border.append(b * n)
	var base := verts.size()
	for k in border.size():
		verts.append(verts[border[k]] - Vector3(0, 6.0 * step, 0))
		nrm.append(nrm[border[k]])
	for k in border.size():
		var k2 := (k + 1) % border.size()
		var a0: int = border[k]
		var a1: int = border[k2]
		var d0 := base + k
		var d1 := base + k2
		idx.append_array([a0, d0, a1, a1, d0, d1, a0, a1, d0, a1, d1, d0])   # both sides
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(cx, 0.0, cz)
	return mi

func generate() -> void:
	if map_dir != "":
		load_map(map_dir)
		return
	heights.resize(N * N)
	for j in N:
		var z := -HALF + j * CELL
		for i in N:
			var x := -HALF + i * CELL
			heights[j * N + i] = _raw_height(x, z)
	# landing sites
	_add_pad("Main helipad", Vector3(0.0, 0.0, 0.0), 26.0, 60.0, 0.0)
	_add_pad("Field LZ", Vector3(valley_center_x(-1450.0) - 60.0, 0.0, -1450.0), 20.0, 40.0, 0.0)
	# pinnacle: highest grid point in a box on the east ridge
	var best := Vector3.ZERO
	var best_h := -1e9
	for j in range(_idx(-1500.0), _idx(-700.0)):
		for i in range(_idx(700.0), _idx(1250.0)):
			var h := heights[j * N + i]
			if h > best_h:
				best_h = h
				best = Vector3(-HALF + i * CELL, h, -HALF + j * CELL)
	_add_pad("Pinnacle LZ", best, 9.0, 18.0, 0.0)
	_build_mesh()

func _idx(c: float) -> int:
	return clampi(int(round((c + HALF) / CELL)), 0, N - 1)

## Flattens terrain around a pad (radius = flat area, blend = transition width)
func _add_pad(pad_name: String, p: Vector3, radius: float, blend: float, hdg: float) -> void:
	var h0 := height_at_raw_grid(p.x, p.z)
	var r_tot := radius + blend
	for j in range(_idx(p.z - r_tot), _idx(p.z + r_tot) + 1):
		for i in range(_idx(p.x - r_tot), _idx(p.x + r_tot) + 1):
			var x := -HALF + i * CELL
			var z := -HALF + j * CELL
			var d := Vector2(x - p.x, z - p.z).length()
			if d <= r_tot:
				var t := smoothstep(radius, r_tot, d)
				heights[j * N + i] = lerpf(h0, heights[j * N + i], t)
	pads[pad_name] = {"pos": Vector3(p.x, h0, p.z), "radius": radius, "heading": hdg}

func height_at_raw_grid(x: float, z: float) -> float:
	return _grid_height(x, z)

func _grid_height(x: float, z: float) -> float:
	var gx := clampf((x + HALF) / CELL, 0.0, N - 1.001)
	var gz := clampf((z + HALF) / CELL, 0.0, N - 1.001)
	var i := int(gx)
	var j := int(gz)
	var fx := gx - i
	var fz := gz - j
	var h00 := heights[j * N + i]
	var h10 := heights[j * N + i + 1]
	var h01 := heights[(j + 1) * N + i]
	var h11 := heights[(j + 1) * N + i + 1]
	# same triangulation as the mesh: diagonal from (0,0) to (1,1)
	if fx >= fz:
		return h00 + (h10 - h00) * fx + (h11 - h10) * fz
	return h00 + (h11 - h01) * fx + (h01 - h00) * fz

## Ground height used by the flight model (terrain plus building roofs).
func height_at(x: float, z: float) -> float:
	var h := _grid_height(x, z)
	var cell = _bld_grid.get(Vector2i(floori(x / BUCKET), floori(z / BUCKET)))
	if cell == null:
		return h
	for k in cell:
		var b: Dictionary = buildings[k]
		var mn: Vector3 = b["min"]
		var mx: Vector3 = b["max"]
		if x >= mn.x and x <= mx.x and z >= mn.z and z <= mx.z:
			h = maxf(h, mx.y)
	return h

func normal_at(x: float, z: float) -> Vector3:
	var e := 2.0
	var hx := _grid_height(x + e, z) - _grid_height(x - e, z)
	var hz := _grid_height(x, z + e) - _grid_height(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()

func add_building(center: Vector3, size: Vector3) -> void:
	var b := {"min": center - Vector3(size.x, 0.0, size.z) * 0.5, "max": center + Vector3(size.x * 0.5, size.y, size.z * 0.5)}
	buildings.append(b)
	var k := buildings.size() - 1
	var mn: Vector3 = b["min"]
	var mx: Vector3 = b["max"]
	for gx in range(floori(mn.x / BUCKET), floori(mx.x / BUCKET) + 1):
		for gz in range(floori(mn.z / BUCKET), floori(mx.z / BUCKET) + 1):
			var key := Vector2i(gx, gz)
			if not _bld_grid.has(key):
				_bld_grid[key] = []
			_bld_grid[key].append(k)

func _build_mesh() -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize(N * N)
	norms.resize(N * N)
	for j in N:
		for i in N:
			var x := -HALF + i * CELL
			var z := -HALF + j * CELL
			verts[j * N + i] = Vector3(x, heights[j * N + i], z)
	for j in N:
		for i in N:
			var il := maxi(i - 1, 0)
			var ir := mini(i + 1, N - 1)
			var jd := maxi(j - 1, 0)
			var ju := mini(j + 1, N - 1)
			var hx := heights[j * N + ir] - heights[j * N + il]
			var hz := heights[ju * N + i] - heights[jd * N + i]
			norms[j * N + i] = Vector3(-hx / ((ir - il) * CELL), 1.0, -hz / ((ju - jd) * CELL)).normalized()
	for j in N - 1:
		for i in N - 1:
			var a := j * N + i
			var b := a + 1
			var c := a + N
			var d := c + 1
			# triangles (a, b, d) and (a, d, c): clockwise seen from above (Godot front face)
			idx.append_array([a, b, d, a, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	var mat := ShaderMaterial.new()
	if ortho:
		mat.shader = load("res://shaders/terrain_photo.gdshader")
		mat.set_shader_parameter("photo", ortho)
		mat.set_shader_parameter("map_size", SIZE)
	else:
		mat.shader = load("res://shaders/terrain.gdshader")
	mesh_instance.material_override = mat
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	_build_far_plane()

func _build_far_plane() -> void:
	# far ground ring so the horizon never shows a void
	var far := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40000, 40000)
	far.mesh = pm
	var hmin := 240.0
	if ortho:
		hmin = 1e9
		for v in heights:
			hmin = minf(hmin, v)
		hmin -= 3.0
	far.position = Vector3(0, hmin, 0)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.60, 0.50, 0.39) if ortho else Color(0.36, 0.40, 0.33)
	fm.roughness = 1.0
	far.material_override = fm
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far)

func set_detail(level: int) -> void:
	if photo_material:
		photo_material.set_shader_parameter("detail", level)
	elif mesh_instance and mesh_instance.material_override:
		(mesh_instance.material_override as ShaderMaterial).set_shader_parameter("detail", level)
