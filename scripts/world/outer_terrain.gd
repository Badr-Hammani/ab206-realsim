extends Node3D
## Real 3D terrain for the whole 98 x 98 km region around a real map (Copernicus GLO-30 DEM at 32 m),
## around the detailed 16 km core of terrain.gd. Shows the phosphate mine pits east of Khouribga, the
## plateau edge to the north and the hills further out, draped with the region photo (and the live
## HD photo through the same shader).
## Levels, swapped by distance from the camera:
##   chunk  8 x 8 km, a point every 256 m   (always present, far away)
##   tile   2 x 2 km, a point every 64 m    (chunks near the camera are split into 16 tiles)
##   fine   2 x 2 km, a point every 32 m    (tiles close to the camera; full DEM detail)
## Meshes are built on demand, at most a few milliseconds per frame. Where the outer terrain meets the
## core, its points inside the core sink 4 m below the core surface so no crack can show.

var terrain                    # terrain.gd
var material: ShaderMaterial
const CH := 256                # cells per chunk (8192 m at 32 m)
const TL := 64                 # cells per tile (2048 m)
## [split chunks within (m), fine tiles within (m)] per preset Low, Medium, High, Ultra
const PROFILE := [[2500.0, 0.0], [3500.0, 1800.0], [5000.0, 2800.0], [7000.0, 4200.0]]
const BUILD_MS := 6
var split_dist := 3500.0
var fine_dist := 1800.0
var chunks := {}               # Vector2i -> MeshInstance3D (coarse)
var tiles := {}                # Vector2i -> {"step": int, "mi": MeshInstance3D}
var nc := 0                    # chunks per side
var _split := {}               # chunks currently split into tiles
var built_meshes := 0

func build() -> void:
	nc = (terrain.ON - 1) / CH
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/terrain_photo.gdshader")
	material.set_shader_parameter("map_size", terrain.OHALF * 2.0)
	material.set_shader_parameter("photo", terrain.region_photo(terrain.season))
	material.set_shader_parameter("detail", 1)
	material.set_shader_parameter("photo_gain", terrain.photo_gain())
	for cy in nc:
		for cx in nc:
			var mi := _mesh(cx * CH, cy * CH, CH, 8, 40.0)
			if mi:
				chunks[Vector2i(cx, cy)] = mi

func set_photo(t: Texture2D) -> void:
	if t:
		material.set_shader_parameter("photo", t)

func set_detail(level: int) -> void:
	material.set_shader_parameter("detail", level)

func set_profile(p: int) -> void:
	var r: Array = PROFILE[clampi(p, 0, PROFILE.size() - 1)]
	split_dist = r[0]
	fine_dist = r[1]

static func _rect_dist(c: Vector2, r: Rect2) -> float:
	var dx := maxf(maxf(r.position.x - c.x, 0.0), c.x - r.end.x)
	var dz := maxf(maxf(r.position.y - c.y, 0.0), c.y - r.end.y)
	return sqrt(dx * dx + dz * dz)

func _cell_rect(i0: int, j0: int, cells: int) -> Rect2:
	var o: float = -terrain.OHALF
	return Rect2(o + i0 * terrain.OCELL, o + j0 * terrain.OCELL, cells * terrain.OCELL, cells * terrain.OCELL)

func _process(_d: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := Vector2(cam.global_position.x, cam.global_position.z)
	var t0 := Time.get_ticks_msec()
	var per := CH / TL
	for key in chunks:
		var ck: Vector2i = key
		var split := _rect_dist(c, _cell_rect(ck.x * CH, ck.y * CH, CH)) < split_dist
		if not split and not _split.has(ck):
			continue
		if not split:
			_split.erase(ck)
		else:
			_split[ck] = true
		var ready := true
		for ty in per:
			for tx in per:
				var tk := Vector2i(ck.x * per + tx, ck.y * per + ty)
				var want := 0
				if split:
					want = 1 if fine_dist > 0.0 and _rect_dist(c, _cell_rect(tk.x * TL, tk.y * TL, TL)) < fine_dist else 2
				var have: Dictionary = tiles.get(tk, {})
				if want == 0:
					if not have.is_empty():
						(have["mi"] as Node).queue_free()
						tiles.erase(tk)
					continue
				if not have.is_empty() and int(have["step"]) == want:
					continue
				# build (or rebuild at the other step) within the frame budget
				if Time.get_ticks_msec() - t0 > BUILD_MS:
					ready = ready and not have.is_empty()
					continue
				var mi := _mesh(tk.x * TL, tk.y * TL, TL, want, 8.0 * want)
				if not have.is_empty():
					(have["mi"] as Node).queue_free()
				if mi:
					tiles[tk] = {"step": want, "mi": mi}
				else:
					tiles[tk] = {"step": want, "mi": Node3D.new()}
					add_child(tiles[tk]["mi"])
		# a split chunk stays visible until all its tiles exist (no holes while they build)
		(chunks[key] as MeshInstance3D).visible = not split or not ready

## Height of an outer grid point; points inside the core sink under the core's surface.
func _h(i: int, j: int) -> float:
	var x: float = -terrain.OHALF + i * terrain.OCELL
	var z: float = -terrain.OHALF + j * terrain.OCELL
	var hc: float = terrain.HALF
	if absf(x) < hc and absf(z) < hc:
		return terrain._grid_height(x, z) - 4.0
	if absf(x) <= hc and absf(z) <= hc:
		return terrain._grid_height(x, z)     # exactly on the core's edge: same height as the core
	return terrain.outer_point(i, j)

## Mesh for cells [i0, i0+cells) x [j0, j0+cells) with a point every `step` cells, skirts hanging
## `skirt` m. Quads entirely inside the core are left out. Returns null when nothing is left.
func _mesh(i0: int, j0: int, cells: int, step: int, skirt: float) -> MeshInstance3D:
	var n := cells / step + 1
	var cell: float = terrain.OCELL
	var hc: float = terrain.HALF
	var cx: float = -terrain.OHALF + (i0 + cells * 0.5) * cell
	var cz: float = -terrain.OHALF + (j0 + cells * 0.5) * cell
	# whole mesh inside the core: nothing to draw
	if absf(cx) + cells * 0.5 * cell < hc and absf(cz) + cells * 0.5 * cell < hc:
		return null
	var verts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize(n * n)
	nrm.resize(n * n)
	var hs := PackedFloat32Array()
	hs.resize((n + 2) * (n + 2))
	for b in range(-1, n + 1):
		for a in range(-1, n + 1):
			hs[(b + 1) * (n + 2) + a + 1] = _h(i0 + a * step, j0 + b * step)
	var d := 2.0 * step * cell
	for b in n:
		for a in n:
			var k := (b + 1) * (n + 2) + a + 1
			var h := hs[k]
			verts[b * n + a] = Vector3(-terrain.OHALF + (i0 + a * step) * cell - cx, h, -terrain.OHALF + (j0 + b * step) * cell - cz)
			nrm[b * n + a] = Vector3(-(hs[k + 1] - hs[k - 1]) / d, 1.0, -(hs[k + n + 2] - hs[k - n - 2]) / d).normalized()
	var inside := func(a: int, b: int) -> bool:
		var x: float = verts[b * n + a].x + cx
		var z: float = verts[b * n + a].z + cz
		return absf(x) < hc and absf(z) < hc
	var quads := 0
	for b in n - 1:
		for a in n - 1:
			if inside.call(a, b) and inside.call(a + 1, b) and inside.call(a, b + 1) and inside.call(a + 1, b + 1):
				continue
			var p := b * n + a
			idx.append_array([p, p + 1, p + n + 1, p, p + n + 1, p + n])
			quads += 1
	if quads == 0:
		return null
	# skirts around the mesh border
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
		verts.append(verts[border[k]] - Vector3(0, skirt, 0))
		nrm.append(nrm[border[k]])
	for k in border.size():
		var k2 := (k + 1) % border.size()
		var a0: int = border[k]
		var a1: int = border[k2]
		var d0 := base + k
		var d1 := base + k2
		idx.append_array([a0, d0, a1, a1, d0, d1, a0, a1, d0, a1, d1, d0])
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
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	built_meshes += 1
	return mi
