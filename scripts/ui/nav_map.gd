extends CanvasLayer
## Moving map for real maps (Khouribga): satellite photo, helicopter, runway and pads.
## K cycles small corner map -> big map (pauses, mouse to pin points and draw zones) -> off.
## Shift+K drops a pin where the helicopter is. Clicking a pin makes it the navigation target:
## bearing, distance and time to go are shown on screen. Pins and zones are saved per map in
## user://nav_marks_<map>.json.

signal closed

enum Mode { OFF, SMALL, BIG }
const ZONE_COLORS := [Color(0.95, 0.25, 0.2), Color(1.0, 0.8, 0.2), Color(0.3, 0.9, 0.4), Color(0.35, 0.7, 1.0)]
const ZONE_NAMES := ["No-fly", "Caution", "Training", "Other"]
const SMALL_SIZE := Vector2(300, 300)

var main                      # main.gd
var terrain                   # terrain.gd (real map)
var map_id := ""
var mode := Mode.OFF
var pins: Array = []          # [{"name": String, "x": float, "z": float}]
var zones: Array = []         # [{"name": String, "color": int, "pts": [[x, z], ...]}]
var target := -1              # index into pins, -1 = none
var trail: PackedVector2Array = PackedVector2Array()
var tool := "pin"             # big map click tool: "pin" or "zone"
var zone_color := 0
var draft: PackedVector2Array = PackedVector2Array()   # zone being drawn
var small_mpp := 10.0         # metres per screen pixel, small map
var big_mpp := 12.0
var big_centre := Vector2.ZERO
var follow := true

var small_view: Control
var small_box: PanelContainer
var big_root: PanelContainer
var big_view: Control
var nav_label: Label
var info_label: Label
var name_edit: LineEdit
var tool_buttons := {}
var color_buttons: Array[Button] = []
var region := {}             # region.json: towns and main roads of the 64 km area
var region_photo: ImageTexture
var region_roads: Array = []  # [{"cls": int, "pts": PackedVector2Array, "box": Rect2}]
var mouse_pos := Vector2(-1, -1)
var streets: Array = []       # detailed map streets: {"kind", "w", "pts", "box"} (OSM, 1,088 km)
var pitches: Array = []       # sports pitches: [corners PackedVector2Array]
const STREET_MPP := 7.0       # streets drawn as lines below this many metres per pixel
## motorway, trunk/primary, secondary, tertiary: colour, width
const ROAD_STYLE := [[Color(1.0, 0.55, 0.25), 3.0], [Color(1.0, 0.85, 0.35), 2.4], [Color(1.0, 0.95, 0.75), 1.7], [Color(0.95, 0.95, 0.95, 0.8), 1.1], [Color(0.2, 0.2, 0.2), 2.0]]
var markers: Node3D           # 3D beams at the pins, so they are visible while flying
var _trail_t := 0.0
var _drag_from := Vector2.ZERO
var _dragging := false
var _press_pos := Vector2.ZERO

func available() -> bool:
	return terrain != null and terrain.ortho != null

func setup(m, t, id: String) -> void:
	main = m
	terrain = t
	map_id = id
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_load_region()
	_load_streets()
	_build_small()
	_build_big()
	nav_label = Label.new()
	nav_label.add_theme_font_size_override("font_size", 15)
	nav_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55))
	nav_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	nav_label.add_theme_constant_override("outline_size", 4)
	add_child(nav_label)
	set_mode(Mode.OFF)
	markers = Node3D.new()
	markers.name = "NavMarkers"
	main.world.add_child(markers)
	_rebuild_markers()

# ------------------------------------------------------------------ public
func cycle() -> void:
	match mode:
		Mode.OFF:
			set_mode(Mode.SMALL)
		Mode.SMALL:
			set_mode(Mode.BIG)
		_:
			set_mode(Mode.OFF)

func is_big() -> bool:
	return mode == Mode.BIG

func set_mode(m: int) -> void:
	var was_big := mode == Mode.BIG
	mode = m
	if small_box:
		small_box.visible = mode == Mode.SMALL
	if big_root:
		big_root.visible = mode == Mode.BIG
	if mode == Mode.BIG:
		follow = true
		big_centre = heli_xz()
		draft.clear()
		_refresh_info()
	elif was_big:
		draft.clear()
		_save()
		closed.emit()

func zoom_small(f: float) -> void:
	small_mpp = clampf(small_mpp * f, 2.0, 40.0)

## Pin at the helicopter's position (J key).
func drop_pin_here() -> String:
	var p := heli_xz()
	var nm := "P%d" % _next_number()
	pins.append({"name": nm, "x": p.x, "z": p.y})
	_save()
	_refresh_info()
	return nm

func heli_xz() -> Vector2:
	return Vector2(main.fdm.pos.x, main.fdm.pos.z)

## Bearing (deg true), distance (m) and ETE text to the target pin; empty if none.
func target_text() -> String:
	if target < 0 or target >= pins.size():
		return ""
	var p: Dictionary = pins[target]
	var d := Vector2(float(p["x"]), float(p["z"])) - heli_xz()
	var dist := d.length()
	var brg := fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0)
	var gs: float = Vector2(main.fdm.vel.x, main.fdm.vel.z).length()
	var ete := ""
	if gs > 3.0:
		var s := int(dist / gs)
		ete = "   ETE %d:%02d" % [s / 60, s % 60]
	var rel := wrapf(brg - main.fdm.heading_deg(), -180.0, 180.0)
	var turn := "ahead" if absf(rel) < 5.0 else ("turn %s %.0f°" % ["right" if rel > 0 else "left", absf(rel)])
	return "TO %s   %03.0f°   %s   (%s)%s" % [p["name"], brg, _dist_text(dist), turn, ete]

func zone_at(xz: Vector2) -> int:
	for i in range(zones.size() - 1, -1, -1):
		if Geometry2D.is_point_in_polygon(xz, _zone_poly(i)):
			return i
	return -1

# ------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	if main == null or not available():
		if nav_label:
			nav_label.visible = false
		return
	if not main.paused:
		_trail_t += delta
		if _trail_t > 2.0:
			_trail_t = 0.0
			var h := heli_xz()
			if trail.is_empty() or trail[trail.size() - 1].distance_to(h) > 15.0:
				trail.append(h)
				if trail.size() > 300:
					trail.remove_at(0)
	var t := target_text()
	var zi := zone_at(heli_xz())
	if zi >= 0:
		t += ("\n" if t != "" else "") + "INSIDE ZONE: %s (%s)" % [zones[zi]["name"], ZONE_NAMES[int(zones[zi]["color"])]]
	nav_label.text = t
	nav_label.visible = t != "" and mode != Mode.BIG
	var vp := get_viewport().get_visible_rect().size
	nav_label.position = Vector2(14, vp.y - SMALL_SIZE.y - 100) if mode == Mode.SMALL else Vector2(14, vp.y - 90)
	if mode == Mode.SMALL:
		small_box.position = Vector2(12, vp.y - SMALL_SIZE.y - 46)
		small_view.queue_redraw()
	elif mode == Mode.BIG:
		big_root.position = Vector2(20, 20)
		big_root.size = vp - Vector2(40, 40)
		if follow:
			big_centre = heli_xz()
		var lim := float(region.get("size_m", terrain.SIZE)) * 0.5
		big_centre = big_centre.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
		big_view.queue_redraw()

# ------------------------------------------------------------------ UI
func _style(alpha: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.09, alpha)
	sb.border_color = Color(1, 1, 1, 0.25)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(4)
	return sb

func _build_small() -> void:
	small_box = PanelContainer.new()
	small_box.add_theme_stylebox_override("panel", _style(0.75))
	small_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(small_box)
	small_view = Control.new()
	small_view.custom_minimum_size = SMALL_SIZE
	small_view.clip_contents = true
	small_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	small_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	small_view.draw.connect(func() -> void: _draw_map(small_view, heli_xz(), small_mpp, false))
	small_box.add_child(small_view)

func _btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _build_big() -> void:
	big_root = PanelContainer.new()
	big_root.add_theme_stylebox_override("panel", _style(0.92))
	add_child(big_root)
	var vb := VBoxContainer.new()
	big_root.add_child(vb)
	var bar := HBoxContainer.new()
	vb.add_child(bar)
	var title := Label.new()
	title.text = "  KHOURIBGA MAP   "
	title.add_theme_font_size_override("font_size", 16)
	bar.add_child(title)
	tool_buttons["pin"] = _btn(bar, "Pin point", func() -> void: _set_tool("pin"))
	tool_buttons["zone"] = _btn(bar, "Draw zone", func() -> void: _set_tool("zone"))
	for i in ZONE_COLORS.size():
		var cb := _btn(bar, ZONE_NAMES[i], func() -> void: zone_color = i; _refresh_info())
		cb.add_theme_color_override("font_color", ZONE_COLORS[i])
		color_buttons.append(cb)
	_btn(bar, "Finish zone", _finish_zone)
	_btn(bar, "Undo point", func() -> void:
		if draft.size() > 0:
			draft.remove_at(draft.size() - 1))
	_btn(bar, "Centre on helicopter", func() -> void: follow = true)
	_btn(bar, "Clear target", func() -> void: target = -1; _save(); _refresh_info())
	_btn(bar, "Close (K / Esc)", func() -> void: set_mode(Mode.OFF))
	var hb := HBoxContainer.new()
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(hb)
	big_view = Control.new()
	big_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	big_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	big_view.clip_contents = true
	big_view.mouse_filter = Control.MOUSE_FILTER_STOP
	big_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	big_view.draw.connect(func() -> void: _draw_map(big_view, big_centre, big_mpp, true))
	big_view.gui_input.connect(_big_input)
	hb.add_child(big_view)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(300, 0)
	hb.add_child(side)
	info_label = Label.new()
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.custom_minimum_size = Vector2(290, 0)
	info_label.add_theme_font_size_override("font_size", 14)
	side.add_child(info_label)
	var nl := Label.new()
	nl.text = "Name of the selected pin / last zone:"
	side.add_child(nl)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "type a name, Enter"
	name_edit.text_submitted.connect(_rename)
	side.add_child(name_edit)
	_btn(side, "Delete selected pin", func() -> void: _delete_pin(target))
	_btn(side, "Delete last zone", func() -> void:
		if zones.size() > 0:
			zones.remove_at(zones.size() - 1)
			_save()
			_refresh_info())
	_set_tool("pin")

func _set_tool(t: String) -> void:
	tool = t
	draft.clear()
	for k in tool_buttons:
		(tool_buttons[k] as Button).modulate = Color(1, 1, 0.5) if k == t else Color(1, 1, 1)
	_refresh_info()

func _refresh_info() -> void:
	if info_label == null:
		return
	var s := ""
	if tool == "pin":
		s += "PIN TOOL: click on the map to add a point. Click a point to fly to it. Right-click a point to delete it.\n"
	else:
		s += "ZONE TOOL (%s): click the corners of the zone, then Finish zone. Right-click deletes a zone.\n" % ZONE_NAMES[zone_color]
	s += "Wheel: zoom   Drag: move the map   Shift+K in flight: pin where you are\n\n"
	s += "Points (%d):\n" % pins.size()
	for i in pins.size():
		var p: Dictionary = pins[i]
		var ll := _latlon(Vector2(float(p["x"]), float(p["z"])))
		s += "%s %s   %.5f, %.5f   %s\n" % [">" if i == target else " ", p["name"], ll.x, ll.y, _dist_text(Vector2(float(p["x"]), float(p["z"])).distance_to(heli_xz()))]
	s += "\nZones (%d):\n" % zones.size()
	for z in zones:
		s += "  %s  (%s, %d corners)\n" % [z["name"], ZONE_NAMES[int(z["color"])], (z["pts"] as Array).size()]
	info_label.text = s
	if name_edit:
		name_edit.text = str(pins[target]["name"]) if target >= 0 and target < pins.size() else ""

# ------------------------------------------------------------------ big map input
func _big_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 0.8)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.25)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and mb.double_click and tool == "zone":
				_finish_zone()
				return
			if mb.pressed:
				_press_pos = mb.position
				_drag_from = mb.position
				_dragging = false
			elif not _dragging:
				_click(mb.position)
			_dragging = _dragging and mb.pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_right_click(mb.position)
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		mouse_pos = mm.position
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if _dragging or mm.position.distance_to(_press_pos) > 6.0:
				_dragging = true
				follow = false
				big_centre -= (mm.position - _drag_from) * big_mpp
				_drag_from = mm.position

func _zoom_at(screen: Vector2, f: float) -> void:
	var before := _to_world(big_view, big_centre, big_mpp, screen)
	big_mpp = clampf(big_mpp * f, 0.5, 50.0)
	var after := _to_world(big_view, big_centre, big_mpp, screen)
	big_centre += before - after
	if f < 1.0:
		follow = false

func _click(screen: Vector2) -> void:
	var w := _to_world(big_view, big_centre, big_mpp, screen)
	var hit := _pin_near(screen)
	if tool == "pin":
		if hit >= 0:
			target = hit
		else:
			pins.append({"name": "P%d" % _next_number(), "x": w.x, "z": w.y})
			target = pins.size() - 1
	else:
		draft.append(w)
	_save()
	_refresh_info()

func _right_click(screen: Vector2) -> void:
	var hit := _pin_near(screen)
	if hit >= 0:
		_delete_pin(hit)
		return
	if tool == "zone" and draft.size() > 0:
		draft.remove_at(draft.size() - 1)
		return
	var zi := zone_at(_to_world(big_view, big_centre, big_mpp, screen))
	if zi >= 0:
		zones.remove_at(zi)
		_save()
		_refresh_info()

func _finish_zone() -> void:
	if draft.size() < 3:
		draft.clear()
		return
	var pts: Array = []
	for p in draft:
		pts.append([snappedf(p.x, 0.1), snappedf(p.y, 0.1)])
	zones.append({"name": "%s %d" % [ZONE_NAMES[zone_color], zones.size() + 1], "color": zone_color, "pts": pts})
	draft.clear()
	_save()
	_refresh_info()

func _rename(t: String) -> void:
	t = t.strip_edges()
	if t == "":
		return
	if target >= 0 and target < pins.size():
		pins[target]["name"] = t
	elif zones.size() > 0:
		zones[zones.size() - 1]["name"] = t
	_save()
	_refresh_info()
	name_edit.release_focus()

func _delete_pin(i: int) -> void:
	if i < 0 or i >= pins.size():
		return
	pins.remove_at(i)
	if target == i:
		target = -1
	elif target > i:
		target -= 1
	_save()
	_refresh_info()

func _pin_near(screen: Vector2) -> int:
	for i in pins.size():
		var p: Dictionary = pins[i]
		var s := _to_screen(big_view, big_centre, big_mpp, Vector2(float(p["x"]), float(p["z"])))
		if s.distance_to(screen) < 12.0:
			return i
	return -1

func _next_number() -> int:
	var n := 1
	for p in pins:
		var s := str(p["name"])
		if s.begins_with("P") and s.substr(1).is_valid_int():
			n = maxi(n, int(s.substr(1)) + 1)
	return n

# ------------------------------------------------------------------ drawing
func _to_screen(v: Control, c: Vector2, mpp: float, xz: Vector2) -> Vector2:
	return v.size * 0.5 + (xz - c) / mpp

func _to_world(v: Control, c: Vector2, mpp: float, s: Vector2) -> Vector2:
	return c + (s - v.size * 0.5) * mpp

func _zone_poly(i: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in zones[i]["pts"]:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out

## Text labels are placed in priority order and skipped where they would overlap one already drawn.
var _placed: Array[Rect2] = []

func _label(v: Control, at: Vector2, text: String, size: int, col: Color, force := false) -> bool:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var r := Rect2(at + Vector2(-2, -size), Vector2(w + 4, size + 4))
	if not force:
		if not Rect2(Vector2.ZERO, v.size).encloses(r):
			return false
		for q in _placed:
			if q.intersects(r):
				return false
	_placed.append(r)
	v.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.85))
	v.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return true

func _draw_map(v: Control, c: Vector2, mpp: float, big: bool) -> void:
	if not available():
		return
	_placed.clear()
	var size_m: float = terrain.SIZE
	var half := size_m * 0.5
	var view_world := Rect2(_to_world(v, c, mpp, Vector2.ZERO), v.size * mpp)
	v.draw_rect(Rect2(Vector2.ZERO, v.size), Color(0.55, 0.48, 0.38))
	# wide area photo (64 km, 32 m/px) under the detailed map photo (16 km, 8 m/px)
	if region_photo:
		var rh := float(region.get("size_m", 65536.0)) * 0.5
		v.draw_texture_rect(region_photo, Rect2(_to_screen(v, c, mpp, Vector2(-rh, -rh)), Vector2(rh, rh) * 2.0 / mpp), false)
	var tl := _to_screen(v, c, mpp, Vector2(-half, -half))
	v.draw_texture_rect(terrain.ortho, Rect2(tl, Vector2(size_m, size_m) / mpp), false)
	if region_photo and mpp > 12.0:
		# edge of the area with 3D houses, roads and full-detail ground
		v.draw_rect(Rect2(tl, Vector2(size_m, size_m) / mpp), Color(1, 1, 1, 0.35), false, 1.0)
	# main roads and railways of the region
	for r in region_roads:
		var cls := int(r["cls"])
		if cls == 3 and mpp > 25.0:
			continue
		if not view_world.intersects(r["box"]):
			continue
		var pts: PackedVector2Array = r["pts"]
		var sp := PackedVector2Array()
		sp.resize(pts.size())
		for k in pts.size():
			sp[k] = v.size * 0.5 + (pts[k] - c) / mpp
		var st: Array = ROAD_STYLE[cls]
		if cls == 4:
			v.draw_polyline(sp, Color(0.15, 0.15, 0.15, 0.9), 2.0)
			for k in range(0, sp.size() - 1, 2):
				v.draw_line(sp[k], sp[k + 1], Color(0.95, 0.95, 0.95, 0.9), 1.0)
		else:
			v.draw_polyline(sp, Color(0, 0, 0, 0.45), float(st[1]) + 1.5)
			v.draw_polyline(sp, st[0], float(st[1]))
	if mpp < STREET_MPP:
		_draw_streets(v, c, mpp, view_world)
	var font := ThemeDB.fallback_font
	var fs := 13
	# runway and pads
	var rw: Dictionary = terrain.map_meta["airport"]["runway"]
	var e0 := Vector2(float(rw["ends"][0][0]), float(rw["ends"][0][1]))
	var e1 := Vector2(float(rw["ends"][1][0]), float(rw["ends"][1][1]))
	v.draw_line(_to_screen(v, c, mpp, e0), _to_screen(v, c, mpp, e1), Color(0.15, 0.15, 0.15, 0.9), maxf(3.0, float(rw["width"]) / mpp))
	v.draw_line(_to_screen(v, c, mpp, e0), _to_screen(v, c, mpp, e1), Color(1, 1, 1, 0.8), 1.0)
	var pad_pos: Array[Vector2] = []
	for pn in terrain.pads:
		var pp: Vector3 = terrain.pads[pn]["pos"]
		var s := _to_screen(v, c, mpp, Vector2(pp.x, pp.z))
		pad_pos.append(s)
		v.draw_circle(s, 6.0, Color(0.1, 0.4, 0.9, 0.9))
		v.draw_string(font, s + Vector2(-4, 4), "H", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	# zones
	for i in zones.size():
		var poly := PackedVector2Array()
		for p in _zone_poly(i):
			poly.append(_to_screen(v, c, mpp, p))
		var col: Color = ZONE_COLORS[int(zones[i]["color"])]
		if Geometry2D.triangulate_polygon(poly).size() > 0:
			v.draw_colored_polygon(poly, Color(col.r, col.g, col.b, 0.22))
		var ring := poly.duplicate()
		ring.append(poly[0])
		v.draw_polyline(ring, col, 2.0)
	if draft.size() > 0:
		var dp := PackedVector2Array()
		for p in draft:
			dp.append(_to_screen(v, c, mpp, p))
		if dp.size() > 1:
			v.draw_polyline(dp, ZONE_COLORS[zone_color], 2.0)
		for p in dp:
			v.draw_circle(p, 4.0, ZONE_COLORS[zone_color])
	# trail
	var h := heli_xz()
	var hs := _to_screen(v, c, mpp, h)
	if trail.size() > 1:
		var tp := PackedVector2Array()
		for p in trail:
			tp.append(_to_screen(v, c, mpp, p))
		tp.append(hs)
		v.draw_polyline(tp, Color(1.0, 0.3, 0.9, 0.7), 1.5)
	# range rings around the helicopter
	var ring_m := _nice(mpp * 120.0)
	for k in [1, 2]:
		var rr: float = ring_m * k / mpp
		v.draw_arc(hs, rr, 0.0, TAU, 96, Color(1, 1, 1, 0.35), 1.0)
		_label(v, hs + Vector2(rr * 0.71 + 3, -rr * 0.71), _dist_text(ring_m * k), 11, Color(1, 1, 1, 0.7))
	# pins, the line to the target, helicopter
	for i in pins.size():
		var p: Dictionary = pins[i]
		var s := _to_screen(v, c, mpp, Vector2(float(p["x"]), float(p["z"])))
		if i == target:
			v.draw_dashed_line(hs, s, Color(1, 0.95, 0.3), 2.0, 8.0)
	_placed.append(Rect2(hs - Vector2(14, 14), Vector2(28, 28)))
	for i in pins.size():
		var p: Dictionary = pins[i]
		var s := _to_screen(v, c, mpp, Vector2(float(p["x"]), float(p["z"])))
		var pc := Color(1, 0.95, 0.3) if i == target else Color(1, 0.45, 0.1)
		v.draw_circle(s + Vector2(0, -10), 6.0, pc)
		v.draw_line(s + Vector2(0, -5), s, pc, 2.0)
		v.draw_circle(s + Vector2(0, -10), 2.5, Color(0.1, 0.1, 0.1))
		_label(v, s + Vector2(8, -6), str(p["name"]), fs, Color.WHITE, i == target)
	# zone names, airport, pads, towns, landmarks: in that priority, no overlaps
	for i in zones.size():
		var ctr := Vector2.ZERO
		var poly := _zone_poly(i)
		for p in poly:
			ctr += p
		var zs := _to_screen(v, c, mpp, ctr / poly.size())
		_label(v, zs, str(zones[i]["name"]), fs, ZONE_COLORS[int(zones[i]["color"])])
	var mid := _to_screen(v, c, mpp, (e0 + e1) * 0.5)
	var des: Array = rw["designators"]
	if not _label(v, mid + Vector2(10, 18), "GMMK  RWY %s/%s  %d ft" % [des[0], des[1], int(terrain.map_meta["airport"].get("elevation_ft_published", 0))], 12, Color(0.85, 0.95, 1.0)):
		_label(v, mid + Vector2(10, 18), "GMMK", 12, Color(0.85, 0.95, 1.0))
	if big or mpp < 6.0:
		var k := 0
		for pn in terrain.pads:
			_label(v, pad_pos[k] + Vector2(9, 4), str(pn), 12, Color(0.8, 0.9, 1.0))
			k += 1
	for t in region.get("towns", []):
		var pop := int(t[3])
		var kind := int(t[4])
		if mpp > 30.0 and pop < 9000 and kind < 2:
			continue
		var ts := _to_screen(v, c, mpp, Vector2(float(t[1]), float(t[2])))
		if not Rect2(Vector2.ZERO, v.size).has_point(ts):
			continue
		var tsz := 16 if kind == 3 else (14 if kind == 2 or pop > 15000 else 12)
		if kind == 3 and mpp < 4.0:
			continue          # inside the city: the streets and landmarks say enough
		if _label(v, ts + Vector2(6, 5), str(t[0]), tsz, Color(1.0, 0.97, 0.88)):
			v.draw_circle(ts, 3.5 if kind >= 2 else 2.5, Color(0, 0, 0, 0.8))
			v.draw_circle(ts, 2.5 if kind >= 2 else 1.6, Color(1, 1, 1))
	if big:
		for lm in terrain.map_meta.get("landmarks", []):
			var ls := _to_screen(v, c, mpp, Vector2(float(lm["x"]), float(lm["z"])))
			if not Rect2(Vector2.ZERO, v.size).has_point(ls):
				continue
			if mpp < 8.0 and _label(v, ls + Vector2(5, 4), str(lm["name"]), 11, Color(1, 1, 1, 0.85)):
				v.draw_circle(ls, 2.5, Color(1, 1, 1, 0.8))
	# helicopter arrow (north up)
	var a := deg_to_rad(main.fdm.heading_deg())
	var fwd := Vector2(sin(a), -cos(a))
	var rt := Vector2(-fwd.y, fwd.x)
	var tri := PackedVector2Array([hs + fwd * 12.0, hs - fwd * 8.0 + rt * 7.0, hs - fwd * 4.0, hs - fwd * 8.0 - rt * 7.0])
	v.draw_colored_polygon(tri, Color(1, 1, 1))
	v.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[3], tri[0]]), Color(0, 0, 0), 1.5)
	# north arrow and scale bar
	var nc := Vector2(v.size.x - 20, 26)
	v.draw_colored_polygon(PackedVector2Array([nc + Vector2(0, -14), nc + Vector2(6, 4), nc + Vector2(0, 0), nc + Vector2(-6, 4)]), Color.WHITE)
	v.draw_string_outline(font, nc + Vector2(-5, 20), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0))
	v.draw_string(font, nc + Vector2(-5, 20), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	var bar_m := _nice(mpp * 100.0)
	var bl := Vector2(10, v.size.y - 12)
	v.draw_line(bl, bl + Vector2(bar_m / mpp, 0), Color(0, 0, 0), 5.0)
	v.draw_line(bl, bl + Vector2(bar_m / mpp, 0), Color(1, 1, 1), 2.0)
	_label(v, bl + Vector2(0, -6), _dist_text(bar_m), 12, Color.WHITE, true)
	# cursor readout (big map)
	if big and Rect2(Vector2.ZERO, v.size).has_point(mouse_pos):
		var w := _to_world(v, c, mpp, mouse_pos)
		var d := w - h
		var ll := _latlon(w)
		var txt := "Cursor: %03.0f°  %s from you   %.5f, %.5f" % [fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0), _dist_text(d.length()), ll.x, ll.y]
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		_label(v, Vector2(v.size.x - tw - 12, v.size.y - 12), txt, 13, Color(1, 1, 0.8), true)

static func _nice(m: float) -> float:
	for s in [50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0]:
		if s >= m * 0.6:
			return s
	return 20000.0

static func _dist_text(m: float) -> String:
	return "%.0f m" % m if m < 1000.0 else "%.1f km" % (m / 1000.0)

func _latlon(xz: Vector2) -> Vector2:
	var lat0 := float(terrain.map_meta.get("origin_lat", 0.0))
	var lon0 := float(terrain.map_meta.get("origin_lon", 0.0))
	return Vector2(lat0 - xz.y / 111320.0, lon0 + xz.x / (111320.0 * cos(deg_to_rad(lat0))))

# ------------------------------------------------------------------ save / load
func _load_region() -> void:
	if terrain == null or terrain.map_dir == "":
		return
	var p: String = terrain.map_dir + "/region.json"
	if not FileAccess.file_exists(p):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not (d is Dictionary):
		return
	region = d
	for r in region.get("roads", []):
		var pts := PackedVector2Array()
		for q in r[1]:
			pts.append(Vector2(float(q[0]), float(q[1])))
		if pts.size() < 2:
			continue
		var bx := Rect2(pts[0], Vector2.ZERO)
		for q in pts:
			bx = bx.expand(q)
		region_roads.append({"cls": int(r[0]), "pts": pts, "box": bx.grow(50.0)})
	set_season(str(terrain.season))

## Street map layer: every OSM street, track and the railway as clean lines (sharper than the photo
## when zoomed in), plus sports pitches. Only what is on screen is drawn.
func _draw_streets(v: Control, c: Vector2, mpp: float, view_world: Rect2) -> void:
	var fade := clampf((STREET_MPP - mpp) / 2.0, 0.0, 1.0)
	for pc in pitches:
		var cp := PackedVector2Array()
		for q in pc:
			cp.append(v.size * 0.5 + (q - c) / mpp)
		v.draw_colored_polygon(cp, Color(0.35, 0.62, 0.3, 0.75 * fade))
		cp.append(cp[0])
		v.draw_polyline(cp, Color(1, 1, 1, 0.8 * fade), 1.0)
	for pass_i in 2:
		for r in streets:
			if not view_world.intersects(r["box"]):
				continue
			var kind := int(r["kind"])
			var w := float(r["w"])
			var pts: PackedVector2Array = r["pts"]
			var sp := PackedVector2Array()
			sp.resize(pts.size())
			for k in pts.size():
				sp[k] = v.size * 0.5 + (pts[k] - c) / mpp
			var px := maxf(1.0, w / mpp)
			if pass_i == 0:
				if kind == 0:
					v.draw_polyline(sp, Color(0.25, 0.25, 0.25, 0.7 * fade), px + 2.0)
			else:
				if kind == 0:
					var col := Color(1.0, 0.9, 0.55) if w >= 8.0 else Color(0.98, 0.98, 0.96)
					v.draw_polyline(sp, Color(col.r, col.g, col.b, 0.95 * fade), px)
				elif kind == 1:
					v.draw_polyline(sp, Color(0.62, 0.45, 0.28, 0.9 * fade), maxf(1.0, px * 0.8))
				else:
					v.draw_polyline(sp, Color(0.15, 0.15, 0.15, fade), 2.5)
					for k in range(0, sp.size() - 1, 2):
						v.draw_line(sp[k], sp[k + 1], Color(1, 1, 1, fade), 1.2)

func _load_streets() -> void:
	for r in terrain.map_meta.get("roads", []):
		var pts := PackedVector2Array()
		for q in r[2]:
			pts.append(Vector2(float(q[0]), float(q[1])))
		if pts.size() < 2:
			continue
		var bx := Rect2(pts[0], Vector2.ZERO)
		for q in pts:
			bx = bx.expand(q)
		streets.append({"kind": int(r[0]), "w": float(r[1]), "pts": pts, "box": bx.grow(20.0)})
	for a in terrain.map_meta.get("areas", []):
		if int(a[0]) != 1 or a.size() < 3:
			continue
		var rc: Array = a[2]
		var ctr := Vector2(float(rc[0]), float(rc[1]))
		var u := Vector2(float(rc[2]), float(rc[3]))
		var vv := Vector2(-u.y, u.x)
		var hl := float(rc[4]) * 0.5
		var hw := float(rc[5]) * 0.5
		pitches.append(PackedVector2Array([ctr + u * hl + vv * hw, ctr - u * hl + vv * hw, ctr - u * hl - vv * hw, ctr + u * hl - vv * hw]))

## Wide-area photo for the current season (the detailed photo is swapped by the terrain).
func set_season(s: String) -> void:
	var photos: Dictionary = region.get("photos", {})
	if photos.is_empty():
		return
	var f: String = photos.get(s, photos.values()[0])
	var img := Image.new()
	if img.load_jpg_from_buffer(FileAccess.get_file_as_bytes(terrain.map_dir + "/" + f)) == OK:
		img.generate_mipmaps()
		# 4096 px: compressed on the GPU (about 11 MB instead of 90 MB) so integrated graphics stay smooth
		if DisplayServer.get_name() != "headless":
			img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_SRGB)
		region_photo = ImageTexture.create_from_image(img)

func _path() -> String:
	return "user://nav_marks_%s.json" % map_id

func _rebuild_markers() -> void:
	if markers == null:
		return
	for ch in markers.get_children():
		ch.queue_free()
	for i in pins.size():
		var p: Dictionary = pins[i]
		var x := float(p["x"])
		var z := float(p["z"])
		var g: float = terrain.height_at(x, z)
		var col := Color(1, 0.95, 0.3) if i == target else Color(1, 0.5, 0.1)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(col.r, col.g, col.b, 0.45)
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.2
		cyl.bottom_radius = 1.2
		cyl.height = 120.0
		cyl.radial_segments = 8
		cyl.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(x, g + 60.0, z)
		markers.add_child(mi)
		var lb := Label3D.new()
		lb.text = str(p["name"])
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.fixed_size = true
		lb.pixel_size = 0.0012
		lb.font_size = 28
		lb.outline_size = 8
		lb.no_depth_test = true
		lb.modulate = col
		lb.position = Vector3(x, g + 126.0, z)
		markers.add_child(lb)

func _save() -> void:
	_rebuild_markers()
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"pins": pins, "zones": zones, "target": target}, " "))

func _load() -> void:
	if not FileAccess.file_exists(_path()):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path()))
	if d is Dictionary:
		pins = d.get("pins", [])
		zones = d.get("zones", [])
		target = int(d.get("target", -1))
		if target >= pins.size():
			target = -1
