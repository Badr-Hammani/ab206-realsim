extends CanvasLayer
## On-screen touch controls for phones and tablets (web build).
## Left strip: COLLECTIVE (drag up/down, the lever stays where you leave it, like friction on).
## Bottom left: PEDALS (drag left/right, stays where you leave it; acts on the pedal trim).
## Right pad: CYCLIC (drag, relative like the mouse cyclic, the stick stays where you leave it).
## Top right buttons: menu, camera, instrument panel, resets, throttle, centre cyclic.
## All inputs write the same values the keyboard/mouse path uses (Controls node), so the
## flight model sees no difference.

var main
var controls
var root: Control
var font: Font
var active := false

# touch index -> zone name
var _touch_zone := {}
var _touch_last := {}
var _thr_target := 1.0
var _thr_driving := false
var _buttons: Array = []   # [rect, label, action]
var _flash := {}           # action -> time

const COL_BG := Color(0.0, 0.0, 0.0, 0.28)
const COL_EDGE := Color(1.0, 1.0, 1.0, 0.55)
const COL_FILL := Color(0.45, 0.85, 1.0, 0.55)
const COL_TEXT := Color(1, 1, 1, 0.92)

func _ready() -> void:
	layer = 8
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.draw.connect(_draw_all)
	font = ThemeDB.fallback_font
	visible = false

func enable() -> void:
	if active:
		return
	active = true
	visible = true
	controls.mouse_cyclic = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main.hud.show_telemetry = false
	_thr_target = controls.throttle
	main.hud.status.visible = false
	main.hud.ctrl_view.visible = false
	main.instructor.force("TOUCH CONTROLS: left strip = collective, bottom slider = pedals, right pad = cyclic. Raise the collective slowly and slide the pedals left as the torque builds. MENU for weather, weight and graphics.")

# ---------------------------------------------------------------- layout
func _size() -> Vector2:
	return root.get_viewport_rect().size

func _coll_rect() -> Rect2:
	var s := _size()
	return Rect2(18, s.y * 0.20, 150, s.y * 0.75)

func _pedal_rect() -> Rect2:
	var s := _size()
	return Rect2(190, s.y - 140, minf(480.0, s.x * 0.30), 120)

func _cyc_center() -> Vector2:
	var s := _size()
	var r := _cyc_radius()
	return Vector2(s.x - r - 40, s.y - r - 40)

func _cyc_radius() -> float:
	return clampf(_size().y * 0.24, 140.0, 260.0)

func _layout_buttons() -> void:
	var s := _size()
	var items := [
		["MENU", "menu"], ["CAMERA", "cam"], ["PANEL", "panel"], ["HELP", "help"],
		["PAD", "pad"], ["HOVER", "hover"], ["AUTO", "auto"], ["CTR CYC", "center"],
	]
	_buttons.clear()
	var bw := 118.0
	var bh := 62.0
	var gap := 8.0
	var x0 := s.x - 4.0 * (bw + gap) - 6.0
	for i in items.size():
		var row := i / 4
		var col := i % 4
		var r := Rect2(x0 + col * (bw + gap), 10 + row * (bh + gap), bw, bh)
		_buttons.append([r, items[i][0], items[i][1]])
	# throttle twist-grip button above the pedals
	var thr_label := "THROTTLE: OPEN" if _thr_target > 0.5 else "THROTTLE: IDLE"
	_buttons.append([Rect2(190, s.y - 250, 230, 62), thr_label, "throttle"])

# ---------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not active:
		enable()
	if not active or not visible:
		return
	if event is InputEventScreenTouch:
		var p: Vector2 = event.position
		if event.pressed:
			var z := _zone_at(p)
			if z == "":
				return
			if z.begins_with("btn:"):
				_press_button(z.substr(4))
			else:
				_touch_zone[event.index] = z
				_touch_last[event.index] = p
			get_viewport().set_input_as_handled()
		else:
			if _touch_zone.has(event.index):
				_touch_zone.erase(event.index)
				_touch_last.erase(event.index)
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _touch_zone.has(event.index):
		var p: Vector2 = event.position
		var d: Vector2 = p - _touch_last[event.index]
		_touch_last[event.index] = p
		match _touch_zone[event.index]:
			"coll":
				controls.collective = clampf(controls.collective - d.y / (_coll_rect().size.y * 1.1), 0.0, 1.0)
			"pedal":
				controls.pedal_trim = clampf(controls.pedal_trim + d.x / (_pedal_rect().size.x * 0.5), -1.0, 1.0)
			"cyc":
				var k := 1.0 / (_cyc_radius() * 1.6)
				controls.stick_mouse.x = clampf(controls.stick_mouse.x + d.x * k, -1.0, 1.0)
				controls.stick_mouse.y = clampf(controls.stick_mouse.y - d.y * k, -1.0, 1.0)
		get_viewport().set_input_as_handled()

func _zone_at(p: Vector2) -> String:
	_layout_buttons()
	for b in _buttons:
		if (b[0] as Rect2).grow(6).has_point(p):
			return "btn:" + b[2]
	if _coll_rect().grow(30).has_point(p):
		return "coll"
	if _pedal_rect().grow(30).has_point(p):
		return "pedal"
	if p.distance_to(_cyc_center()) < _cyc_radius() * 1.25:
		return "cyc"
	return ""

func _press_button(a: String) -> void:
	_flash[a] = 0.25
	match a:
		"menu":
			main.menu.open()
			main._set_paused(true)
		"cam":
			main.cam_rig.cycle()
		"panel":
			main.show_panel_2d = not main.show_panel_2d
		"help":
			main.hud.help.visible = not main.hud.help.visible
		"pad":
			main.reset_on_pad()
		"hover":
			main.reset_hover()
		"auto":
			main.reset_autorotation()
		"center":
			controls.stick_mouse = Vector2.ZERO
		"throttle":
			_thr_target = 0.0 if _thr_target > 0.5 else 1.0
			_thr_driving = true

# ---------------------------------------------------------------- update/draw
func _process(dt: float) -> void:
	if not active:
		return
	visible = not main.paused
	if _thr_driving and not main.paused:
		controls.throttle = move_toward(controls.throttle, _thr_target, 0.6 * dt)
		if is_equal_approx(controls.throttle, _thr_target):
			_thr_driving = false
	elif not _thr_driving:
		_thr_target = 1.0 if controls.throttle > 0.5 else 0.0
	for k in _flash.keys():
		_flash[k] -= dt
		if _flash[k] <= 0.0:
			_flash.erase(k)
	root.queue_redraw()

func _text(pos: Vector2, s: String, size := 20, col := COL_TEXT, center := false) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := pos - Vector2(w * 0.5, 0) if center else pos
	root.draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.8))
	root.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _draw_all() -> void:
	var s := _size()
	if s.y > s.x:
		root.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.75))
		_text(Vector2(s.x * 0.5, s.y * 0.5), "Turn your phone sideways (landscape)", 30, COL_TEXT, true)
		return
	_layout_buttons()
	# collective
	var cr := _coll_rect()
	root.draw_rect(cr, COL_BG)
	var fh: float = cr.size.y * controls.collective
	root.draw_rect(Rect2(cr.position.x, cr.end.y - fh, cr.size.x, fh), COL_FILL)
	root.draw_rect(cr, COL_EDGE, false, 2.0)
	var ly: float = cr.end.y - fh
	root.draw_rect(Rect2(cr.position.x - 6, ly - 8, cr.size.x + 12, 16), Color(1, 1, 1, 0.85))
	_text(Vector2(cr.get_center().x, cr.position.y - 12), "COLLECTIVE %d%%" % int(round(controls.collective * 100.0)), 18, COL_TEXT, true)
	_text(Vector2(cr.get_center().x, cr.end.y - 10 - fh * 0.0 + 0), "drag", 16, Color(1, 1, 1, 0.5), true)
	# pedals
	var pr := _pedal_rect()
	root.draw_rect(pr, COL_BG)
	root.draw_rect(pr, COL_EDGE, false, 2.0)
	var mid := pr.get_center()
	root.draw_line(Vector2(mid.x, pr.position.y + 8), Vector2(mid.x, pr.end.y - 8), Color(1, 1, 1, 0.35), 2.0)
	var px: float = mid.x + controls.pedal * pr.size.x * 0.5
	root.draw_rect(Rect2(px - 10, pr.position.y + 6, 20, pr.size.y - 12), Color(1, 1, 1, 0.85))
	_text(Vector2(mid.x, pr.position.y - 10), "PEDALS %+d%%  (left pedal to hover)" % int(round(controls.pedal * 100.0)), 18, COL_TEXT, true)
	_text(Vector2(pr.position.x + 10, pr.end.y - 12), "L", 22)
	_text(Vector2(pr.end.x - 26, pr.end.y - 12), "R", 22)
	# cyclic
	var cc := _cyc_center()
	var rr := _cyc_radius()
	root.draw_circle(cc, rr, COL_BG)
	root.draw_arc(cc, rr, 0, TAU, 64, COL_EDGE, 2.0)
	root.draw_line(cc - Vector2(rr, 0), cc + Vector2(rr, 0), Color(1, 1, 1, 0.25), 1.5)
	root.draw_line(cc - Vector2(0, rr), cc + Vector2(0, rr), Color(1, 1, 1, 0.25), 1.5)
	var kp := cc + Vector2(controls.cyclic_lat, -controls.cyclic_lon) * rr
	root.draw_circle(kp, 30, Color(1, 1, 1, 0.8))
	root.draw_circle(kp, 22, COL_FILL)
	_text(Vector2(cc.x, cc.y - rr - 12), "CYCLIC (stays where you leave it)", 18, COL_TEXT, true)
	# buttons
	for b in _buttons:
		var r: Rect2 = b[0]
		var hot: bool = _flash.has(b[2])
		root.draw_rect(r, Color(0.45, 0.85, 1.0, 0.6) if hot else Color(0, 0, 0, 0.45))
		root.draw_rect(r, COL_EDGE, false, 2.0)
		_text(Vector2(r.get_center().x, r.get_center().y + 7), b[1], 18, COL_TEXT, true)
	_text(Vector2(190, s.y - 262), "N2 %d%%  NR %d%%  TQ %d%%" % [int(main.fdm.n2_pct()), int(main.fdm.nr_pct()), int(maxf(main.fdm.torque_pct, 0.0))], 18)
