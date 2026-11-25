extends RefCounted
## Buildings and trees found in the 0.5 m aerial photo of Khouribga (tools/ai/extract.py writes
## data/maps/khouribga/ai_features.json). Inside the analysed area ("coverage") they replace the
## estimated houses and trees of map.json, so what you fly over matches the photo:
##   buildings: real footprint polygons, height from the length of their shadow in the photo
##   trees: real crown positions and sizes
## Outside the analysed area the estimated houses and trees stay.

const PATH := "res://data/maps/khouribga/ai_features.json"
const TILE := 512.0

var data := {}
var cov := PackedByteArray()
var cov_n := 0
var cov_cell := 32.0
var cov_origin := -8192.0
var material: ShaderMaterial
var tiles: Array[GeometryInstance3D] = []
var building_count := 0
var tree_count := 0

func load_data() -> bool:
	if not FileAccess.file_exists(PATH):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(d) != TYPE_DICTIONARY:
		return false
	data = d
	cov = (str(d.get("coverage", "")) as String).hex_decode()
	cov_n = int(d.get("cov_n", 0))
	cov_cell = float(d.get("cov_cell", 32.0))
	cov_origin = float(d.get("cov_origin", -8192.0))
	return cov_n > 0

## True where the photo was analysed (estimated houses/trees are not drawn there).
func covered(x: float, z: float) -> bool:
	if cov_n == 0:
		return false
	var i := floori((x - cov_origin) / cov_cell)
	var j := floori((z - cov_origin) / cov_cell)
	if i < 0 or j < 0 or i >= cov_n or j >= cov_n:
		return false
	var bit := j * cov_n + i
	return (cov[bit >> 3] >> (7 - (bit & 7))) & 1 == 1

func trees() -> Array:
	var out: Array = []
	for t in data.get("trees", []):
		# extract.py gives the crown radius; the sim's tree mesh has a 2.4 m crown at scale 1
		out.append([float(t[0]), float(t[1]), clampf(float(t[2]) / 2.4, 0.45, 2.6)])
	return out

func build_buildings(world, terrain) -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/ai_building.gdshader")
	var groups := {}
	for b in data.get("buildings", []):
		var poly: Array = b[1]
		if poly.size() < 6:
			continue
		var key := Vector2i(floori(float(poly[0]) / TILE), floori(float(poly[1]) / TILE))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(b)
	for key in groups:
		var c := Vector3((key.x + 0.5) * TILE, 0.0, (key.y + 0.5) * TILE)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for b in groups[key]:
			_add_building(st, b, c, terrain)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = material
		mi.position = c
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(mi)
		tiles.append(mi)

func _add_building(st: SurfaceTool, b: Array, c: Vector3, terrain) -> void:
	var h := float(b[0])
	var flat: Array = b[1]
	var pts := PackedVector2Array()
	for k in range(0, flat.size() - 1, 2):
		pts.append(Vector2(float(flat[k]), float(flat[k + 1])))
	if pts.size() < 3:
		return
	# x east, z south: make the outline clockwise seen from above (+y) so walls face outwards
	if Geometry2D.is_polygon_clockwise(pts):
		pts.reverse()
	var lo := INF
	var hi := -INF
	for p in pts:
		var g: float = terrain._grid_height(p.x, p.y)
		lo = minf(lo, g)
		hi = maxf(hi, g)
	var base := lo - 0.5
	var top := hi + h
	var hh := top - base
	var roof_col := Color.html("#" + str(b[2])) if b.size() > 2 else Color(0.8, 0.75, 0.65)
	var tris := Geometry2D.triangulate_polygon(pts)
	if tris.is_empty():
		return
	st.set_color(roof_col)
	st.set_uv2(Vector2(hh, 0.0))
	# flat normals set by hand (generate_normals smoothed roof into walls: blobby "snow" roofs)
	st.set_normal(Vector3.UP)
	for k in range(0, tris.size(), 3):
		for m in [0, 2, 1]:
			var p: Vector2 = pts[tris[k + m]]
			st.set_uv(Vector2(0.0, hh))
			st.add_vertex(Vector3(p.x - c.x, top - c.y, p.y - c.z))
	# walls: outward normal of edge d is (d.y, 0, -d.x) when the shoelace area is positive
	var area := 0.0
	for k in pts.size():
		var p0: Vector2 = pts[k]
		var p1: Vector2 = pts[(k + 1) % pts.size()]
		area += p0.x * p1.y - p1.x * p0.y
	var sgn := 1.0 if area > 0.0 else -1.0
	var along := 0.0
	for k in pts.size():
		var a: Vector2 = pts[k]
		var e: Vector2 = pts[(k + 1) % pts.size()]
		var len := a.distance_to(e)
		var va := Vector3(a.x - c.x, 0.0, a.y - c.z)
		var ve := Vector3(e.x - c.x, 0.0, e.y - c.z)
		var d := (e - a) / maxf(len, 0.001)
		st.set_normal(Vector3(d.y, 0.0, -d.x) * sgn)
		var q := [[va, base, along, 0.0], [ve, base, along + len, 0.0], [ve, top, along + len, hh], [va, top, along, hh]]
		for idx in [0, 2, 1, 0, 3, 2]:
			var v: Array = q[idx]
			st.set_uv(Vector2(v[2], v[3]))
			st.add_vertex((v[0] as Vector3) + Vector3(0.0, float(v[1]), 0.0))
		along += len
	building_count += 1
	var bb := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		bb = bb.expand(p)
	terrain.add_building(Vector3(bb.get_center().x, base, bb.get_center().y), Vector3(bb.size.x, hh, bb.size.y), pts)
