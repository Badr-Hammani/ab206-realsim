extends Node
## Live HD aerial photo on the 3D ground (real maps with a region.json projection, e.g. Khouribga).
## Streams Esri World Imagery web tiles around the camera while you fly and drapes them on the
## terrain through shaders/hd_ground.gdshaderinc:
##   near level  zoom 17, about 1.0 m per pixel at Khouribga (257 m per tile)
##   far level   zoom 15, about 4.0 m per pixel (1 km per tile)
## Window sizes (tiles per side) come from the graphics preset (set_profile). Everything stays in
## memory (GPU texture arrays); on PC tile_fetch.gd also keeps them on disk. Needs internet (or the saved areas); when tiles cannot be
## loaded (offline, blocked by the browser or the page), the Sentinel-2 10 m photo stays.
## Imagery: Esri, Maxar, Earthstar Geographics (credit shown on screen while it is in use).

const HdTiles := preload("res://scripts/ui/hd_tiles.gd")
const TileFetch := preload("res://scripts/world/tile_fetch.gd")
const CREDIT := "HD ground photo © Esri, Maxar, Earthstar Geographics"
const Z_NEAR := 17
const Z_FAR := 15
const Z_CLOSE := 18                   # about 0.5 m per pixel right around the helicopter (High, Ultra)
## [near tiles per side, far tiles per side, close tiles per side] per preset: Low, Medium, High, Ultra
## (close tiles are 128 m: 8 tiles = 1 km square, 12 = 1.5 km)
const PROFILE := [[0, 0, 0], [6, 6, 0], [8, 8, 8], [12, 8, 12]]
const UPLOADS_PER_FRAME := 2
## AI-sharpened 0.5 m photo (tools/ai/upscale.py): 512 px files <cache>/sr18/<x>_<y>.webp, 0.25 m look.
## Where they exist the close level uses them instead of the 256 px download (PC only).
const SR_DIR := "sr18"
const SR_LOADS_PER_FRAME := 2
const RETRY_MS := 30000

var url := HdTiles.URL               # tests point this at a local server
var enabled := true
var proj                              # hd_tiles.gd instance, used only for its projection maths
var fetch                             # tile_fetch.gd
var materials: Array[ShaderMaterial] = []
var levels: Array = []                # [near, far] dictionaries (see _make_level)
var limit := 0.0                      # half size of the region the projection covers (m)
var _ready_q: Array = []              # [key, Image] waiting for upload
var _failed := {}                     # key -> retry time
var _pending := {}                    # key -> true: loaded, waiting in _ready_q (do not ask again)
var _w := [0, 0, 0]
var credit: Label
var status := "off"                   # off / loading / live / offline / outside
var _last_report := 0
var _offline_at := -1                 # when it gave up; tries again a minute later (signal may return)
var sr_used := 0                      # AI-sharpened tiles placed so far
var _sr_have := {}                    # "x_y" -> true: files present in the sr18 folder

func setup(region: Dictionary) -> bool:
	if not region.has("proj"):
		return false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hd-url="):
			url = a.substr(9)        # test server, e.g. http://127.0.0.1:8765/tile.jpg?%d/%d/%d
	proj = HdTiles.new()
	proj.proj = region["proj"]
	proj.lat0 = float(region["proj"].get("lat0", 0.0))
	proj.lon0 = float(region["proj"].get("lon0", 0.0))
	limit = float(region.get("size_m", 98304.0)) * 0.5 - 500.0
	_scan_sr()
	fetch = TileFetch.new()
	fetch.name = "TileFetch"
	fetch.max_req = 8 if OS.has_feature("web") else 6
	add_child(fetch)
	fetch.tile_ready.connect(func(k: String, img: Image) -> void:
		_pending[k] = true
		_ready_q.append([k, img]))
	fetch.tile_failed.connect(func(k: String) -> void: _failed[k] = Time.get_ticks_msec() + RETRY_MS)
	var cl := CanvasLayer.new()
	cl.layer = 5
	add_child(cl)
	credit = Label.new()
	credit.text = CREDIT
	credit.add_theme_font_size_override("font_size", 11)
	credit.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	credit.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	credit.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	credit.grow_horizontal = Control.GROW_DIRECTION_BOTH
	credit.grow_vertical = Control.GROW_DIRECTION_BEGIN
	credit.position.y -= 2
	credit.visible = false
	cl.add_child(credit)
	return true

## Lists the AI-sharpened tiles once (a few thousand names; cheap).
func _scan_sr() -> void:
	_sr_have.clear()
	if OS.has_feature("web"):
		return
	var d := DirAccess.open(TileFetch.cache_dir + "/" + SR_DIR)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".webp"):
			_sr_have[f.get_basename()] = true
	if not _sr_have.is_empty():
		print("HD ground: %d AI-sharpened 0.25 m tiles available" % _sr_have.size())

func add_material(m: ShaderMaterial) -> void:
	if m and not materials.has(m):
		materials.append(m)
		_push_all(m)

## Graphics preset 0-3 -> window sizes. Low switches HD ground off.
func set_profile(preset: int) -> void:
	var p: Array = PROFILE[clampi(preset, 0, PROFILE.size() - 1)]
	if OS.has_feature("web") and preset >= 3:
		p = PROFILE[2]        # phones: Ultra keeps High's tile window (video memory)
	if OS.has_feature("web"):
		p = [p[0], p[1], 0]   # phones: no 0.5 m level (memory, and texture slots on the web renderer)
	if p[0] == _w[0] and p[1] == _w[1] and p[2] == _w[2]:
		return
	_w = [int(p[0]), int(p[1]), int(p[2])]
	levels.clear()
	_ready_q.clear()
	_pending.clear()
	if _w[0] > 0:
		levels.append(_make_level(Z_NEAR, _w[0], "n"))
	if _w[1] > 0:
		levels.append(_make_level(Z_FAR, _w[1], "f"))
	if _w[2] > 0:
		levels.append(_make_level(Z_CLOSE, _w[2], "u", 512 if not _sr_have.is_empty() else 256))
	for m in materials:
		_push_all(m)

func _make_level(z: int, w: int, sfx: String, px := 256) -> Dictionary:
	var blank := Image.create(px, px, true, Image.FORMAT_RGBA8)
	blank.fill(Color(0.5, 0.5, 0.5))
	blank.generate_mipmaps()
	var imgs: Array[Image] = []
	for i in w * w:
		imgs.append(blank)
	var tex := Texture2DArray.new()
	tex.create_from_images(imgs)
	var idx := Image.create(w, w, false, Image.FORMAT_RGF)
	idx.fill(Color(-1e5, -1e5, 0))
	var ll: Vector2 = proj.to_latlon(Vector2.ZERO)
	var base: Vector2 = proj.tile_xy(ll.y, ll.x, z).floor()
	return {"z": z, "w": w, "sfx": sfx, "px": px, "tex": tex, "idx": idx, "idx_tex": ImageTexture.create_from_image(idx),
		"base": Vector2i(base), "slots": {}, "fit_at": Vector2(1e9, 1e9), "ax": Vector3.ZERO, "ay": Vector3.ZERO,
		"tile_m": 40075016.7 * cos(deg_to_rad(ll.x)) / float(1 << z), "dirty": false}

## Global web tile coordinates (fractional) of a world x/z point.
func _tile_at(z: int, p: Vector2) -> Vector2:
	var ll: Vector2 = proj.to_latlon(p)
	return proj.tile_xy(ll.y, ll.x, z)

## Affine fit world x/z -> tile coordinates relative to the level base, around point c.
func _fit(L: Dictionary, c: Vector2) -> void:
	var z: int = L["z"]
	var d := 800.0
	var t0 := _tile_at(z, c) - Vector2(L["base"])
	var dx := (_tile_at(z, c + Vector2(d, 0)) - _tile_at(z, c - Vector2(d, 0))) / (2.0 * d)
	var dz := (_tile_at(z, c + Vector2(0, d)) - _tile_at(z, c - Vector2(0, d))) / (2.0 * d)
	L["ax"] = Vector3(dx.x, dz.x, t0.x - dx.x * c.x - dz.x * c.y)
	L["ay"] = Vector3(dx.y, dz.y, t0.y - dx.y * c.x - dz.y * c.y)
	L["fit_at"] = c
	for m in materials:
		_push_fit(m, L)

func _push_fit(m: ShaderMaterial, L: Dictionary) -> void:
	var s: String = L["sfx"]
	m.set_shader_parameter("hd_ax_" + s, L["ax"])
	m.set_shader_parameter("hd_ay_" + s, L["ay"])

func _push_all(m: ShaderMaterial) -> void:
	for s in ["n", "f", "u"]:
		m.set_shader_parameter("hd_r_" + s, 0.0)
	for L in levels:
		var s: String = L["sfx"]
		var w: int = L["w"]
		var b: Vector2i = L["base"]
		m.set_shader_parameter("hd_tex_" + s, L["tex"])
		m.set_shader_parameter("hd_idx_" + s, L["idx_tex"])
		m.set_shader_parameter("hd_w_" + s, float(w))
		m.set_shader_parameter("hd_bm_" + s, Vector2(posmod(b.x, w), posmod(b.y, w)))
		# fade out before the edge of the window around the camera's tile
		m.set_shader_parameter("hd_r_" + s, (float(w) * 0.5 - 0.6) * float(L["tile_m"]))
		_push_fit(m, L)
	m.set_shader_parameter("hd_on", 1.0 if enabled and not levels.is_empty() else 0.0)

func offline() -> bool:
	return fetch != null and fetch.fail_count >= 16 and fetch.ok_count == 0

func set_enabled(on: bool) -> void:
	enabled = on
	if on and fetch:
		fetch.fail_count = 0
		_failed.clear()
	for m in materials:
		m.set_shader_parameter("hd_on", 1.0 if enabled and not levels.is_empty() else 0.0)

func _process(_d: float) -> void:
	if proj == null or levels.is_empty() or not enabled:
		status = "off"
		if credit:
			credit.visible = false
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := Vector2(cam.global_position.x, cam.global_position.z)
	if absf(c.x) > limit or absf(c.y) > limit:
		status = "outside"
		credit.visible = false
		return
	var now := Time.get_ticks_msec()
	if offline():
		if _offline_at < 0:
			_offline_at = now
		elif now - _offline_at > 60000:
			fetch.fail_count = 0
			_failed.clear()
			_offline_at = -1
	var want: Array = []        # [priority, key, level index, tile]
	for li in levels.size():
		var L: Dictionary = levels[li]
		if (L["fit_at"] as Vector2).distance_to(c) > 300.0:
			_fit(L, c)
		var w: int = L["w"]
		var ct := _tile_at(L["z"], c)
		var o := Vector2i(int(floor(ct.x - w * 0.5 + 0.5)), int(floor(ct.y - w * 0.5 + 0.5)))
		L["origin"] = o
		if offline():
			continue
		for ty in range(o.y, o.y + w):
			for tx in range(o.x, o.x + w):
				var slot := Vector2i(posmod(tx, w), posmod(ty, w))
				if L["slots"].get(slot, Vector2i(-999999, -999999)) == Vector2i(tx, ty):
					continue
				var key := "%d/%d/%d" % [L["z"], tx, ty]
				if fetch.is_busy(key) or _pending.has(key) or (_failed.has(key) and now < int(_failed[key])):
					continue
				var dd := Vector2(tx + 0.5, ty + 0.5).distance_to(ct)
				# near tiles first; the far level fills in between (its tiles cover 16 near tiles)
				var zl: int = L["z"]
				want.append([dd * (1.0 if zl == Z_NEAR else (0.6 if zl == Z_CLOSE else 2.5)), key, li, Vector2i(tx, ty)])
	want.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var sr_loads := 0
	for wt in want:
		var t: Vector2i = wt[3]
		var zl: int = levels[wt[2]]["z"]
		var sk := "%d_%d" % [t.x, t.y]
		if zl == Z_CLOSE and _sr_have.has(sk):
			if sr_loads >= SR_LOADS_PER_FRAME:
				continue
			sr_loads += 1
			var img := Image.load_from_file(TileFetch.cache_dir + "/" + SR_DIR + "/" + sk + ".webp")
			if img and not img.is_empty():
				_pending[wt[1]] = true
				_ready_q.append([wt[1], img])
				sr_used += 1
				continue
			_sr_have.erase(sk)
		if not fetch.can_request():
			continue
		fetch.request(wt[1], url % [zl, t.y, t.x])
	# upload a few finished tiles per frame (mipmaps + GPU upload cost a few ms on a phone)
	var n := 0
	while not _ready_q.is_empty() and n < UPLOADS_PER_FRAME:
		var item: Array = _ready_q.pop_front()
		_pending.erase(item[0])
		if _place(item[0], item[1]):
			n += 1
	var live := 0
	for L in levels:
		live += (L["slots"] as Dictionary).size()
		if L["dirty"]:
			(L["idx_tex"] as ImageTexture).update(L["idx"])
			L["dirty"] = false
	var st := "offline" if offline() else ("live" if live > 0 else "loading")
	if st != status:
		print("HD ground: %s -> %s (%d ok, %d failed)" % [status, st, fetch.ok_count, fetch.fail_count])
	status = st
	if live / 25 != _last_report:
		_last_report = live / 25
		print("HD ground: %d tiles on the ground (%d downloaded, %d failed, %d busy)" % [live, fetch.ok_count, fetch.fail_count, fetch.busy()])
	credit.visible = live > 0

func _place(key: String, img: Image) -> bool:
	var p := key.split("/")
	if p.size() != 3:
		return false
	var z := int(p[0])
	var t := Vector2i(int(p[1]), int(p[2]))
	for L in levels:
		if L["z"] != z or not L.has("origin"):
			continue
		var o: Vector2i = L["origin"]
		var w: int = L["w"]
		if t.x < o.x or t.y < o.y or t.x >= o.x + w or t.y >= o.y + w:
			return false     # flew away from it meanwhile
		var px: int = L.get("px", 256)
		if img.get_width() != px or img.get_height() != px:
			img.resize(px, px, Image.INTERPOLATE_BILINEAR if px > img.get_width() else Image.INTERPOLATE_LANCZOS)
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		img.generate_mipmaps()
		var slot := Vector2i(posmod(t.x, w), posmod(t.y, w))
		(L["tex"] as Texture2DArray).update_layer(img, slot.y * w + slot.x)
		L["slots"][slot] = t
		var b: Vector2i = L["base"]
		(L["idx"] as Image).set_pixel(slot.x, slot.y, Color(t.x - b.x, t.y - b.y, 0))
		L["dirty"] = true
		return true
	return false

## Short status for the HUD / settings ("HD ground: live, 140 tiles").
func describe() -> String:
	var live := 0
	for L in levels:
		live += (L["slots"] as Dictionary).size()
	match status:
		"live":
			return "live (%d tiles)" % live + (", %d AI-sharpened" % sr_used if sr_used > 0 else "")
		"loading":
			return "loading..."
		"offline":
			return fetch.blocked_text() + " Showing the 10 m satellite photo."
		"outside":
			return "outside the HD area"
	return "off"
