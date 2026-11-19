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
	check("[M10] moving map: pins, target bearing, zones, saved", pname == "P1" and tt.begins_with("TO North   000°   2.0 km") and inside == 0 and nm.pins.size() == 2 and nm.zones.size() == 1 and nm.markers.get_child_count() >= 4 and nm.region_photo != null and nm.region.get("towns", []).size() > 20 and nm.region_roads.size() > 500, "%s | zone hit %d | reloaded %d pins %d zones | region: %d towns, %d roads" % [tt, inside, nm.pins.size(), nm.zones.size(), nm.region.get("towns", []).size(), nm.region_roads.size()])
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
