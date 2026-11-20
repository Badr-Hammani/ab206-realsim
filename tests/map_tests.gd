extends SceneTree
## Headless tests for the real Khouribga (GMMK) map: loads the real main scene on that map and
## checks heights against published data, ground contact on the helipad, hover power at the
## plateau's density altitude, building collision and load time.
## Run:  godot --headless --path . --script res://tests/map_tests.gd

const DT := 1.0 / 120.0
var main
var passed := 0
var failed := 0
var load_ms := 0

func check(name: String, ok: bool, detail: String) -> void:
	if ok:
		passed += 1
		print("  PASS  %s  (%s)" % [name, detail])
	else:
		failed += 1
		print("  FAIL  %s  (%s)" % [name, detail])

var _saved_settings := ""

func _initialize() -> void:
	# the sim saves settings (including the map) as it runs: keep the user's own file untouched
	if FileAccess.file_exists("user://settings.cfg"):
		_saved_settings = FileAccess.get_file_as_string("user://settings.cfg")
	var t0 := Time.get_ticks_msec()
	main = load("res://scenes/main.tscn").instantiate()
	main.map_override = "khouribga"
	root.add_child(main)
	load_ms = Time.get_ticks_msec() - t0

var _started := false
func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false

func _steps(sec: float) -> void:
	for k in int(sec / DT):
		main._physics_process(DT)

func _run() -> void:
	print("AB206 REALSIM - Khouribga map tests")
	var w = main.world
	var t = w.terrain
	check("[M1] map loaded", w.map_id == "khouribga" and t.N == 1025 and t.ortho != null and t.tiles.size() == 192, "map %s, grid %d (16 m), %d terrain tiles, photo %s, load %d ms" % [w.map_id, t.N, t.tiles.size(), t.ortho != null, load_ms])
	var pad: Vector3 = t.pads["Main helipad"]["pos"]
	check("[M2] helipad elevation vs published 2,552 ft (778 m)", absf(pad.y - 778.0) < 15.0, "%.1f m MSL (%.0f ft)" % [pad.y, pad.y / 0.3048])
	var rw: Dictionary = t.map_meta["airport"]["runway"]
	var e0: Array = rw["ends"][0]
	var e1: Array = rw["ends"][1]
	var h0: float = t.height_at(e0[0], e0[1])
	var h1: float = t.height_at(e1[0], e1[1])
	var mid: float = t.height_at((e0[0] + e1[0]) * 0.5, (e0[1] + e1[1]) * 0.5)
	check("[M3] runway 05/23 is a smooth straight slope", absf(mid - (h0 + h1) * 0.5) < 0.6 and absf(h1 - h0) < 20.0, "ends %.1f / %.1f m, middle %.1f m, heading %.1f true" % [h0, h1, mid, float(rw["true_heading"])])
	var nb: int = t.map_meta["buildings"].size()
	var ntree := 0
	for tt in w.real_map.tree_tiles:
		ntree += tt.multimesh.instance_count
	var nroad: int = t.map_meta["roads"].size()
	check("[M4] buildings, trees and roads present", nb > 10000 and ntree > 1000 and nroad > 5000, "%d buildings, %d trees, %d road segments, %d house tiles" % [nb, ntree, nroad, w.real_map.house_tiles.size()])
	main.apply_preset(0)
	var low: float = w.real_map.house_tiles[0].visibility_range_end
	var tlow: float = t.tiles[0].visibility_range_end
	main.apply_preset(2)
	var high: float = w.real_map.house_tiles[0].visibility_range_end
	var thigh: float = t.tiles[0].visibility_range_end
	main.apply_preset(1)
	check("[M4b] graphics preset sets draw distances", low < high and low > 1000.0 and tlow < thigh and tlow >= 1450.0, "houses drawn to %.0f m on Low, %.0f m on High; fine terrain to %.0f / %.0f m" % [low, high, tlow, thigh])
	var nmin := 0
	for b in t.map_meta["buildings"]:
		if int(b[6]) == 3:
			nmin += 1
	check("[M4d] real OSM landmarks and land use", nmin >= 8 and w.real_map.area_tiles.size() > 0 and t.map_meta["areas"].size() > 50, "%d minaret parts, %d land-use areas in %d meshes" % [nmin, t.map_meta["areas"].size(), w.real_map.area_tiles.size()])
	var nm = main.nav_map
	nm.map_id = "test_tmp"
	nm.pins.clear()
	nm.zones.clear()
	nm.target = -1
	var hx: Vector2 = nm.heli_xz()
	var pname: String = nm.drop_pin_here()
	nm.pins.append({"name": "North", "x": hx.x, "z": hx.y - 2000.0})
	nm.target = 1
	var tt: String = nm.target_text()
	nm.zones.append({"name": "Test zone", "color": 0, "pts": [[hx.x - 50, hx.y - 50], [hx.x + 50, hx.y - 50], [hx.x + 50, hx.y + 50], [hx.x - 50, hx.y + 50]]})
	var inside: int = nm.zone_at(hx)
	nm._save()
	nm.pins.clear()
	nm.zones.clear()
	nm._load()
	nm.set_mode(nm.Mode.SMALL)
	await process_frame
	nm.set_mode(nm.Mode.BIG)
	await process_frame
	await process_frame
	nm.set_mode(nm.Mode.OFF)
	main._set_paused(false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://nav_marks_test_tmp.json"))
	check("[M10] moving map: pins, target bearing, zones, saved", pname == "P1" and tt.begins_with("TO North   000°   2.0 km") and inside == 0 and nm.pins.size() == 2 and nm.zones.size() == 1 and nm.markers.get_child_count() >= 4 and nm.region_photo != null and nm.region.get("towns", []).size() > 20 and nm.region_roads.size() > 500 and nm.streets.size() > 5000 and nm.pitches.size() > 3, "%s | zone hit %d | reloaded %d pins %d zones | region: %d towns, %d roads" % [tt, inside, nm.pins.size(), nm.zones.size(), nm.region.get("towns", []).size(), nm.region_roads.size()])
	# HD aerial tiles: projection accuracy against pyproj, then live download from a local test server
	var hd = nm.hd
	var p1: Vector2 = hd.to_map(-6.6339, 32.8783)
	var p2: Vector2 = hd.to_map(-7.4, 33.3)
	var back: Vector2 = hd.to_latlon(p2)
	var perr := maxf(p1.distance_to(Vector2(29626.243, -2139.758)), p2.distance_to(Vector2(-41866.310, -48953.883)))
	var berr := maxf(absf(back.x - 33.3), absf(back.y + 7.4)) * 111000.0
	hd.url = "http://127.0.0.1:8765/tile.jpg?%d/%d/%d"
	nm.follow = false
	nm.big_centre = hx
	nm.big_mpp = 1.5
	nm.set_mode(nm.Mode.BIG)
	var zz: int = hd.zoom_for(1.5)
	for i in 200:
		await process_frame
		if hd.cache.size() >= 6 and hd.fetch.busy() == 0:
			break
		await create_timer(0.03).timeout
	nm.set_mode(nm.Mode.OFF)
	main._set_paused(false)
	check("[M11] HD photo tiles: placed to the cm, fetched live, cached", perr < 0.05 and berr < 0.5 and zz == 17 and hd.cache.size() >= 6 and hd.fail_count == 0, "projection error %.3f m / back %.3f m, zoom %d at 1.5 m/px, %d tiles loaded, %d failed" % [perr, berr, zz, hd.cache.size(), hd.fail_count])
	# live HD ground photo on the 3D terrain (Ultra profile), tiles from the same local test server
	var hg = w.hd_ground
	hg.url = "http://127.0.0.1:8765/tile.jpg?%d/%d/%d"
	hg.set_enabled(true)      # clears the failures from the blocked real server earlier in this run
	main.apply_preset(3)
	var cam_p: Vector3 = main.get_viewport().get_camera_3d().global_position
	for i in 1200:
		await process_frame
		if hg.levels.size() == 3 and hg.levels[0]["slots"].size() >= 40 and hg.levels[1]["slots"].size() >= 20 and hg.levels[2]["slots"].size() >= 40:
			break
		await create_timer(0.02).timeout
	var Ln: Dictionary = hg.levels[0]
	var q := Vector2(cam_p.x + 900.0, cam_p.z - 700.0)
	var exact: Vector2 = hg._tile_at(17, q) - Vector2(Ln["base"])
	var fitted := Vector2(Ln["ax"].dot(Vector3(q.x, q.y, 1.0)), Ln["ay"].dot(Vector3(q.x, q.y, 1.0)))
	var fit_m: float = exact.distance_to(fitted) * float(Ln["tile_m"])
	var on: float = t.photo_material.get_shader_parameter("hd_on")
	check("[M12] HD ground photo streams onto the 3D terrain", hg.status == "live" and on > 0.5 and Ln["slots"].size() >= 40 and hg.levels[1]["slots"].size() >= 20 and fit_m < 1.0 and Ln["w"] == 12 and hg.levels.size() == 3 and hg.levels[2]["z"] == 18 and hg.levels[2]["slots"].size() >= 40, "%s; 0.5 m level %d, near %d / far %d tiles, tile %.0f m, affine fit error %.2f m at 1.1 km" % [hg.describe(), hg.levels[2]["slots"].size() if hg.levels.size() > 2 else 0, Ln["slots"].size(), hg.levels[1]["slots"].size(), Ln["tile_m"], fit_m])
	await _test_sr(hg, cam_p)
	main.apply_preset(1)
	await _test_prefetch(nm)
	# wide-area 3D terrain (98 km, Copernicus 32 m): mine pit 15.5 km E / 10.9 km S, seams at the core edge
	var ot = t.outer_terrain
	var pit: float = t.height_at(15520.0, 10880.0)
	var rim: float = t.height_at(15520.0 - 320.0, 10880.0)
	var seam := 0.0
	for k in 41:
		var e: float = -t.HALF + k * 409.6
		seam = maxf(seam, absf(t._grid_height(t.HALF + 0.01, e) - t._grid_height(t.HALF - 0.01, e)))
	var cam3: Camera3D = main.get_viewport().get_camera_3d()
	var keep_cam := cam3.global_transform
	cam3.global_position = Vector3(15520.0, pit + 300.0, 10880.0)
	for i in 120:
		await process_frame
	var fine := 0
	for k in ot.tiles:
		if int(ot.tiles[k]["step"]) == 1:
			fine += 1
	cam3.global_transform = keep_cam
	check("[M13] wide 3D terrain: mine pits east of Khouribga, no seams at the core", t.ON == 3073 and absf(pit - 666.8) < 2.0 and rim - pit > 25.0 and seam < 3.0 and ot.chunks.size() > 100 and fine >= 4, "pit %.1f m (rim %.1f m higher), core/outer step at edge max %.2f m, %d chunks, %d fine tiles near the pit" % [pit, rim - pit, seam, ot.chunks.size(), fine])
	var s0: String = w.season
	main.set_season("spring")
	var tex_sp = t.ortho
	main.set_season("summer")
	check("[M4c] season switch swaps the photo", tex_sp != null and t.ortho != tex_sp and w.season == "summer", "spring/summer photos loaded")
	main.set_season(s0)
	var b: Array = t.map_meta["buildings"][200]
	var gh: float = t._grid_height(b[0], b[1])
	var hh: float = t.height_at(b[0], b[1])
	check("[M5] buildings are solid for the flight model", hh > gh + 2.0, "roof %.1f m above ground" % (hh - gh))
	var t1 := Time.get_ticks_usec()
	var acc := 0.0
	for k in 20000:
		acc += t.height_at(1500.0 + k * 0.1, -2500.0 + k * 0.05)
	var us := float(Time.get_ticks_usec() - t1) / 20000.0
	check("[M6] ground lookup stays fast with 40k+ buildings", us < 25.0, "%.2f us per height_at" % us)
	# sitting on the pad, collective down
	main.reset_on_pad()
	_steps(6.0)
	var f = main.fdm
	check("[M7] stays on the helipad deck, engine running", f.on_ground and absf(f.pos.y - f.cg_height - pad.y) < 0.15 and f.vel.length() < 0.1, "skid height %.2f m above deck, speed %.2f m/s, NR %.0f%%" % [f.pos.y - f.cg_height - pad.y, f.vel.length(), f.nr_pct()])
	# trimmed hover at 5 m (in ground effect) and at 150 m (out of ground effect) on the 778 m plateau
	main.reset_hover()
	var tq_ige: float = f.torque_pct
	main._place(pad + Vector3(0, 150.0 + f.cg_height, 0), 0.0, 0.0)
	var tq_oge: float = f.torque_pct
	check("[M8] hover power at Khouribga elevation", tq_oge >= tq_ige and tq_oge < 100.0, "torque IGE 5 m %.0f%%, OGE %.0f%% (ISA%+.0f, %.0f kg)" % [tq_ige, tq_oge, f.atmo.temp_offset_c, f.mass])
	main.reset_on_pad()
	# switching map from the menu reloads the scene on the other map
	current_scene = main
	main.set_map("valle")
	for k in 3:
		await process_frame
	var m2 = current_scene
	check("[M9] menu map switch reloads on the training valley", m2 != null and m2 != main and m2.world.map_id == "valle" and m2.world.terrain.ortho == null, "now on %s" % (m2.world.map_id if m2 else "nothing"))
	print("\n%d passed, %d failed" % [passed, failed])
	if _saved_settings != "":
		var fa := FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		fa.store_string(_saved_settings)
		fa.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	quit(0 if failed == 0 else 1)

## [M14] sharp HD saved on the PC: prefetch of the key areas from the local test server into a test
## cache folder, then the server stops (offline) and the map and 3D ground still load them from disk.
func _test_prefetch(nm) -> void:
	const TF := preload("res://scripts/world/tile_fetch.gd")
	const PF := preload("res://scripts/world/hd_prefetch.gd")
	var keep_dir: String = TF.cache_dir
	TF.cache_dir = "user://hd_cache_test"
	_rm_tree(TF.cache_dir)
	var pf = PF.new()
	pf.url = "http://127.0.0.1:8765/tile.jpg?%d/%d/%d"
	root.add_child(pf)
	pf.setup(main.world.terrain.region, false)
	pf.url = "http://127.0.0.1:8765/tile.jpg?%d/%d/%d"
	var t0 := Time.get_ticks_msec()
	pf.start()
	var total: int = pf.total
	while pf.running() and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	var secs := float(Time.get_ticks_msec() - t0) / 1000.0
	var on_disk := 0
	var cd := DirAccess.open(TF.cache_dir)
	for sub in cd.get_directories():      # one folder per zoom level ("x" for the test server's URL)
		on_disk += DirAccess.open(TF.cache_dir + "/" + sub).get_files().size()
	var marked := FileAccess.file_exists(TF.cache_dir + "/prefetch_v1.done")
	# second run finds everything on disk and downloads nothing
	pf.start()
	var again: int = pf.queue.size()
	# offline: stop the server, then the map at 1 m/px over the city loads only from disk
	var hr := HTTPRequest.new()
	root.add_child(hr)
	hr.request("http://127.0.0.1:8765/quit")
	await hr.request_completed
	var hd = nm.hd
	hd.cache.clear()
	hd.order.clear()
	hd.failed.clear()
	hd.fail_count = 0
	hd.ok_count = 0
	hd.fetch.disk_hits = 0
	nm.follow = false
	nm.big_centre = Vector2(3900, -2900)     # Khouribga city centre
	nm.big_mpp = 1.2
	nm.set_mode(nm.Mode.BIG)
	for i in 120:
		await process_frame
	var hits: int = hd.fetch.disk_hits
	var cached: int = hd.cache.size()
	nm.set_mode(nm.Mode.OFF)
	main._set_paused(false)
	pf.queue_free()
	hr.queue_free()
	_rm_tree(TF.cache_dir)
	TF.cache_dir = keep_dir
	check("[M14] sharp HD saved on the PC (city, GMMK, mines) and used offline", total > 1500 and on_disk == total and marked and again == 0 and hits >= 6 and cached >= 6, "%d tiles in %.0f s, %d files on disk, done mark %s, re-check downloads %d; offline map at 1.2 m/px: %d tiles from disk" % [total, secs, on_disk, marked, again, hits])

## [M15] AI-sharpened 0.25 m tiles (tools/ai/upscale.py, <cache>/sr18/<x>_<y>.webp) replace the
## 256 px zoom-18 tiles of the close level: 512 px layers, loaded from disk, no download for them.
func _test_sr(hg, cam_p: Vector3) -> void:
	const TF := preload("res://scripts/world/tile_fetch.gd")
	var keep_dir: String = TF.cache_dir
	TF.cache_dir = "user://hd_cache_sr_test"
	_rm_tree(TF.cache_dir)
	DirAccess.make_dir_recursive_absolute(TF.cache_dir + "/sr18")
	var ct: Vector2 = hg._tile_at(18, Vector2(cam_p.x, cam_p.z))
	var img := Image.create(512, 512, false, Image.FORMAT_RGB8)
	img.fill(Color(0.9, 0.1, 0.1))
	var made := 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			img.save_webp(TF.cache_dir + "/sr18/%d_%d.webp" % [int(ct.x) + dx, int(ct.y) + dy])
			made += 1
	hg._scan_sr()
	hg._w = [0, 0, 0]
	hg.set_profile(3)
	for i in 600:
		await process_frame
		if hg.sr_used >= made and hg.levels[2]["slots"].size() >= 40:
			break
		await create_timer(0.02).timeout
	var L: Dictionary = hg.levels[2]
	var lay: Image = (L["tex"] as Texture2DArray).get_layer_data(posmod(int(ct.y), L["w"]) * L["w"] + posmod(int(ct.x), L["w"]))
	# headless has no GPU copy of the layer; then check that the slot holds that tile
	var red := lay.get_pixel(256, 256) if lay else Color(1, 0, 0)
	var placed: bool = L["slots"].get(Vector2i(posmod(int(ct.x), L["w"]), posmod(int(ct.y), L["w"]))) == Vector2i(int(ct.x), int(ct.y))
	var ok: bool = L["px"] == 512 and hg.sr_used >= made and placed and red.r > 0.8 and red.g < 0.25 and L["slots"].size() >= 40
	check("[M15] AI-sharpened 0.25 m photo used near the helicopter", ok, "%s; layer %d px, centre pixel %s" % [hg.describe(), L["px"], red])
	_rm_tree(TF.cache_dir)
	TF.cache_dir = keep_dir
	hg._scan_sr()
	hg._w = [0, 0, 0]
	hg.set_profile(3)

func _rm_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for sub in d.get_directories():
		_rm_tree(path + "/" + sub)
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(path)
