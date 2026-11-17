extends Node3D
## Procedural 4 x 4 km test valley ("Valle Bianca", fictional, realistic elevations
## 280-1300 m MSL). The same height grid is used for rendering AND for the flight
## model's skid contact, ground effect and AGL, so what you see is what you hit.

const SIZE := 4096.0
const N := 257                 # vertices per side (16 m spacing)
const CELL := SIZE / float(N - 1)
const HALF := SIZE * 0.5

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

func generate() -> void:
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
	for b in buildings:
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
	buildings.append({"min": center - Vector3(size.x, 0.0, size.z) * 0.5, "max": center + Vector3(size.x * 0.5, size.y, size.z * 0.5)})

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
	mat.shader = load("res://shaders/terrain.gdshader")
	mesh_instance.material_override = mat
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	# far ground ring so the horizon never shows a void
	var far := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40000, 40000)
	far.mesh = pm
	far.position = Vector3(0, 240.0, 0)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.36, 0.40, 0.33)
	fm.roughness = 1.0
	far.material_override = fm
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far)

func set_detail(level: int) -> void:
	if mesh_instance and mesh_instance.material_override:
		(mesh_instance.material_override as ShaderMaterial).set_shader_parameter("detail", level)
