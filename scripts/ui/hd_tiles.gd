extends Node
## HD aerial photo layer for the moving map: web map tiles (Esri World Imagery, about 0.3 to 1 m per
## pixel over Morocco) fetched live from the internet while the big or small map is zoomed in.
## Only tiles on screen are requested, at most MAX_REQ at a time, nearest to the centre first.
## Tiles are kept in memory only (LRU, MAX_CACHE), nothing is saved to disk.
## Tile corners are placed with the cubic lon/lat -> map-metre polynomials from region.json, so they
## line up with the map to well under a metre over the whole 98 km area.

const URL := "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/%d/%d/%d"
const CREDIT := "HD imagery © Esri, Maxar, Earthstar Geographics"
const MAX_REQ := 6
const MAX_CACHE := 600
var max_cache := MAX_CACHE
const Z_MIN := 13
const Z_MAX := 19
const START_MPP := 10.0       # HD tiles are used when zoomed in closer than this (metres per screen px)

var url := URL                # tests point this at a local server
var enabled := true
var proj := {}
var cache := {}               # "z/x/y" -> ImageTexture
var order: Array[String] = [] # LRU, oldest first
var failed := {}              # "z/x/y" -> retry time (msec)
const TileFetch := preload("res://scripts/world/tile_fetch.gd")
var fetch                     # tile_fetch.gd: HTTPRequest on PC, browser <img> loading on the web
var fail_count := 0
var ok_count := 0
var _want: Array = []         # [[dist, key, z, x, y]] wanted this frame
var lat0 := 0.0
var lon0 := 0.0

func setup(p: Dictionary) -> void:
	proj = p
	lat0 = float(p.get("lat0", 0.0))
	lon0 = float(p.get("lon0", 0.0))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hd-url="):
			url = a.substr(9)        # test server, e.g. http://127.0.0.1:8765/tile.jpg?%d/%d/%d
	if OS.has_feature("web"):
		max_cache = 160            # phones: about 55 MB of tiles at most
	fetch = TileFetch.new()
	fetch.max_req = MAX_REQ
	add_child(fetch)
	fetch.tile_ready.connect(_got)
	fetch.tile_failed.connect(_fail)

func active() -> bool:
	return enabled and proj.has("fwd_e")

## Offline / blocked: after 12 failures and no success, stop trying (button turns it back on).
func offline() -> bool:
	return fail_count >= 12 and ok_count == 0

static func _poly(c: Array, u: float, v: float) -> float:
	var s := 0.0
	var k := 0
	for i in 4:
		for j in 4 - i:
			s += float(c[k]) * pow(u, i) * pow(v, j)
			k += 1
	return s

## lon, lat (degrees) -> map x (east), z (south) in metres
func to_map(lon: float, lat: float) -> Vector2:
	var u := lon - lon0
	var v := lat - lat0
	return Vector2(_poly(proj["fwd_e"], u, v), -_poly(proj["fwd_n"], u, v))

## map x, z -> Vector2(lat, lon)
func to_latlon(xz: Vector2) -> Vector2:
	var u := xz.x / 1e4
	var v := -xz.y / 1e4
	return Vector2(lat0 + _poly(proj["inv_lat"], u, v), lon0 + _poly(proj["inv_lon"], u, v))

static func tile_lon(x: float, z: int) -> float:
	return x / float(1 << z) * 360.0 - 180.0

static func tile_lat(y: float, z: int) -> float:
	return rad_to_deg(atan(sinh(PI * (1.0 - 2.0 * y / float(1 << z)))))

static func tile_xy(lon: float, lat: float, z: int) -> Vector2:
	var n := float(1 << z)
	var lr := deg_to_rad(lat)
	return Vector2((lon + 180.0) / 360.0 * n, (1.0 - log(tan(lr) + 1.0 / cos(lr)) / PI) * 0.5 * n)

## Zoom level whose pixels are just finer than the screen pixels.
func zoom_for(mpp: float) -> int:
	var m0 := 156543.034 * cos(deg_to_rad(lat0))
	return clampi(int(ceil(log(m0 / maxf(mpp, 0.05)) / log(2.0))), Z_MIN, Z_MAX)

func _corners(z: int, x: int, y: int) -> PackedVector2Array:
	var w := tile_lon(x, z)
	var e := tile_lon(x + 1, z)
	var nl := tile_lat(y, z)
	var sl := tile_lat(y + 1, z)
	return PackedVector2Array([to_map(w, nl), to_map(e, nl), to_map(e, sl), to_map(w, sl)])

## Draws every HD tile on screen (or a loaded coarser one while it downloads). Returns true when
## something was drawn, so the map shows the credit line.
func draw(v: Control, c: Vector2, mpp: float, view_world: Rect2, limit: float) -> bool:
	if not active() or offline() or mpp >= START_MPP:
		return false
	var z := zoom_for(mpp)
	var a := view_world.intersection(Rect2(-limit, -limit, limit * 2.0, limit * 2.0))
	if a.size.x <= 0.0 or a.size.y <= 0.0:
		return false
	var ll0 := to_latlon(a.position)
	var ll1 := to_latlon(a.end)
	var t0 := tile_xy(ll0.y, ll0.x, z)
	var t1 := tile_xy(ll1.y, ll1.x, z)
	var x0 := int(floor(minf(t0.x, t1.x))) - 1
	var x1 := int(floor(maxf(t0.x, t1.x))) + 1
	var y0 := int(floor(minf(t0.y, t1.y))) - 1
	var y1 := int(floor(maxf(t0.y, t1.y))) + 1
	if (x1 - x0 + 1) * (y1 - y0 + 1) > 400:
		return false
	var drew := false
	var centre := tile_xy(to_latlon(c).y, to_latlon(c).x, z)
	var half := v.size * 0.5
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			var q := _corners(z, tx, ty)
			var sp := PackedVector2Array()
			var bx := Rect2(q[0], Vector2.ZERO)
			for p in q:
				bx = bx.expand(p)
				sp.append(half + (p - c) / mpp)
			if not bx.intersects(view_world):
				continue
			var key := "%d/%d/%d" % [z, tx, ty]
			if cache.has(key):
				_touch(key)
				v.draw_primitive(sp, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]), PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]), cache[key])
				drew = true
				continue
			_want.append([Vector2(tx + 0.5, ty + 0.5).distance_squared_to(centre), key, z, tx, ty])
			# coarser tile already in memory: draw its matching part until this one arrives
			for up in range(1, 5):
				var zz := z - up
				var px := tx >> up
				var py := ty >> up
				var pk := "%d/%d/%d" % [zz, px, py]
				if cache.has(pk):
					var s := 1.0 / float(1 << up)
					var u0 := float(tx - (px << up)) * s
					var v0 := float(ty - (py << up)) * s
					v.draw_primitive(sp, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]), PackedVector2Array([Vector2(u0, v0), Vector2(u0 + s, v0), Vector2(u0 + s, v0 + s), Vector2(u0, v0 + s)]), cache[pk])
					drew = true
					break
	return drew

func _touch(key: String) -> void:
	var i := order.find(key)
	if i >= 0 and i != order.size() - 1:
		order.remove_at(i)
		order.append(key)

func _process(_delta: float) -> void:
	if _want.is_empty() or fetch == null:
		return
	_want.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
	var now := Time.get_ticks_msec()
	for w in _want:
		if not fetch.can_request():
			break
		var key: String = w[1]
		if fetch.is_busy(key) or cache.has(key) or (failed.has(key) and now < int(failed[key])):
			continue
		fetch.request(key, url % [int(w[2]), int(w[4]), int(w[3])])
	_want.clear()

func _fail(key: String) -> void:
	fail_count += 1
	failed[key] = Time.get_ticks_msec() + 30000

func _got(key: String, img: Image) -> void:
	ok_count += 1
	img.generate_mipmaps()
	cache[key] = ImageTexture.create_from_image(img)
	order.append(key)
	while order.size() > max_cache:
		cache.erase(order.pop_front())
