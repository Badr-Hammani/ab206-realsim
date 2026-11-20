extends Node
## Downloads the sharp HD aerial photo for the places you fly most, once, and keeps it on disk
## (user://hd_cache, the same cache tile_fetch.gd uses for the live map and the 3D ground):
##   GMMK airfield         zoom 15-18  (down to about 0.5 m per pixel)
##   Khouribga city        zoom 15-17  (about 1 m), city centre zoom 18
##   Mines north-east/east zoom 15-16  (about 2 m)
## After that the moving map and the 3D ground are sharp there even with no internet, and they
## never wait for a download. PC builds only (phones keep nothing on disk). Starts by itself the
## first time the Khouribga map runs with internet; the big map shows the progress and has a button.
## Imagery: Esri, Maxar, Earthstar Geographics.

const HdTiles := preload("res://scripts/ui/hd_tiles.gd")
const TileFetch := preload("res://scripts/world/tile_fetch.gd")
const AUTO_DELAY_S := 15.0
const PARALLEL := 4

## [name, x0, z0, x1, z1 (map metres, x east, z south), zoom from, zoom to]
const AREAS := [
	["GMMK airfield", -2200.0, -2200.0, 2600.0, 1600.0, 15, 18],
	["Khouribga city", -500.0, -7500.0, 8500.0, 1000.0, 15, 17],
	["City centre", 1800.0, -5200.0, 6200.0, -800.0, 18, 18],
	["Mines north-east and east", 5000.0, -15000.0, 22000.0, 13000.0, 15, 16],
	["Training core 16 km", -8200.0, -8200.0, 8200.0, 8200.0, 15, 15],
]

var url := HdTiles.URL
var proj                      # hd_tiles.gd (projection maths)
var fetch                     # tile_fetch.gd
var queue: Array = []         # [key, url] still to download
var total := 0
var done := 0                 # already on disk or downloaded now
var failed := 0
var state := "idle"           # idle / scanning / running / finished / offline / web
var _ok_run := 0
var _fail_streak := 0
var _auto_at := -1.0

func setup(region: Dictionary, auto_start := true) -> bool:
	if not region.has("proj"):
		return false
	if OS.has_feature("web"):
		state = "web"
		return false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hd-url="):
			url = a.substr(9)
		elif a == "--no-hd-prefetch":
			auto_start = false
	proj = HdTiles.new()
	proj.proj = region["proj"]
	proj.lat0 = float(region["proj"].get("lat0", 0.0))
	proj.lon0 = float(region["proj"].get("lon0", 0.0))
	fetch = TileFetch.new()
	fetch.name = "PrefetchFetch"
	fetch.max_req = PARALLEL
	add_child(fetch)
	fetch.tile_ready.connect(_got)
	fetch.tile_failed.connect(_fail)
	if auto_start and not FileAccess.file_exists(_done_file()):
		_auto_at = AUTO_DELAY_S
	elif FileAccess.file_exists(_done_file()):
		state = "finished"
	return true

## Every tile of every area: [[key, url]] (keys "z/x/y").
func all_tiles() -> Array:
	var out: Array = []
	var seen := {}
	for a in AREAS:
		var ll0: Vector2 = proj.to_latlon(Vector2(a[1], a[2]))   # (lat, lon) north-west corner
		var ll1: Vector2 = proj.to_latlon(Vector2(a[3], a[4]))   # south-east corner
		for z in range(int(a[5]), int(a[6]) + 1):
			var t0: Vector2 = HdTiles.tile_xy(ll0.y, ll0.x, z)
			var t1: Vector2 = HdTiles.tile_xy(ll1.y, ll1.x, z)
			for ty in range(int(floor(minf(t0.y, t1.y))), int(floor(maxf(t0.y, t1.y))) + 1):
				for tx in range(int(floor(minf(t0.x, t1.x))), int(floor(maxf(t0.x, t1.x))) + 1):
					var key := "%d/%d/%d" % [z, tx, ty]
					if seen.has(key):
						continue
					seen[key] = true
					out.append([key, url % [z, ty, tx]])
	return out

func start() -> void:
	if fetch == null:
		return
	state = "scanning"
	queue.clear()
	var tiles := all_tiles()
	total = tiles.size()
	done = 0
	failed = 0
	_ok_run = 0
	_fail_streak = 0
	for t in tiles:
		if TileFetch.on_disk(t[1]):
			done += 1
		else:
			queue.append(t)
	state = "running" if not queue.is_empty() else "finished"
	print("HD prefetch: %d tiles, %d already on disk, %d to download" % [total, done, queue.size()])
	if state == "finished":
		_mark_done()

func stop() -> void:
	queue.clear()
	if state == "running":
		state = "idle"

func running() -> bool:
	return state == "running" or (fetch != null and fetch.busy() > 0)

func progress() -> float:
	return float(done) / float(maxi(total, 1))

## One line for the map ("Sharp HD download: 37% (1520 / 4110 tiles)").
func describe() -> String:
	match state:
		"running":
			return "Downloading sharp HD photo for the city, GMMK and the mines: %d%% (%d / %d)" % [int(progress() * 100.0), done, total]
		"finished":
			return "Sharp HD photo saved on this PC for the city, GMMK and the mines (works offline)"
		"offline":
			return "Sharp HD download paused: no internet. It tries again next time."
		"scanning":
			return "Checking the saved HD photo..."
		"web":
			return ""
	return "Sharp HD photo not downloaded yet"

func _process(delta: float) -> void:
	if _auto_at >= 0.0:
		_auto_at -= delta
		if _auto_at < 0.0:
			start()
	if state != "running":
		return
	while not queue.is_empty() and fetch.busy() < PARALLEL:
		var t: Array = queue.pop_front()
		if not fetch.request(t[0], t[1]):
			queue.push_front(t)
			break
	if queue.is_empty() and fetch.busy() == 0:
		state = "finished"
		print("HD prefetch: finished, %d tiles on disk, %d failed" % [done, failed])
		if failed == 0:
			_mark_done()

func _got(_key: String, _img: Image) -> void:
	done += 1
	_ok_run += 1
	_fail_streak = 0

func _fail(key: String) -> void:
	failed += 1
	if failed <= 5:
		print("HD prefetch: tile %s failed (%s)" % [key, fetch.last_error])
	_fail_streak += 1
	if _fail_streak >= 12 and _ok_run == 0 and state == "running":
		# no internet (or the imagery server refuses): stop now, try again next launch
		queue.clear()
		state = "offline"
		print("HD prefetch: stopped, %d failures in a row" % _fail_streak)

static func _done_file() -> String:
	return TileFetch.cache_dir + "/prefetch_v1.done"

func _mark_done() -> void:
	DirAccess.make_dir_recursive_absolute(TileFetch.cache_dir)
	var f := FileAccess.open(_done_file(), FileAccess.WRITE)
	if f:
		f.store_string("%d tiles\n" % total)
