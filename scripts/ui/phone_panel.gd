extends CanvasLayer
## Phone controller setup (F10): start the phone server, show the address + QR code,
## live status of each phone, calibration and sensitivity settings.

const QR = preload("res://scripts/ui/qr.gd")

var phone          # phone_server.gd
var controls
var root: PanelContainer
var box: VBoxContainer
var live: Label
var bars: Control
var qr_rect: TextureRect
var _qr_for := ""

func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.07, 0.96)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	root.add_theme_stylebox_override("panel", sb)
	root.anchor_left = 0.5
	root.anchor_right = 0.5
	root.anchor_top = 0.5
	root.anchor_bottom = 0.5
	root.offset_left = -480
	root.offset_right = 480
	root.offset_top = -340
	root.offset_bottom = 340
	add_child(root)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	visible = false

func open() -> void:
	visible = true
	_rebuild()

func close() -> void:
	visible = false
	phone.save_config()

func _label(text: String, size := 14, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(560, 0)
	return l

func _slider(parent: Node, text: String, vmin: float, vmax: float, step: float, value: float, fmt: String, cb: Callable) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(250, 0)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = vmin
	s.max_value = vmax
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(220, 22)
	h.add_child(s)
	var vl := Label.new()
	vl.text = fmt % value
	vl.custom_minimum_size = Vector2(80, 0)
	h.add_child(vl)
	s.value_changed.connect(func(v: float) -> void:
		vl.text = fmt % v
		cb.call(v))
	parent.add_child(h)

func _check(parent: Node, text: String, value: bool, cb: Callable) -> void:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = value
	c.toggled.connect(cb)
	parent.add_child(c)

func _rebuild() -> void:
	for c in box.get_children():
		c.queue_free()
	box.add_child(_label("PHONE CONTROLLER  (F10 or Esc to close - settings are saved)", 17))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	box.add_child(top)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(left)
	qr_rect = TextureRect.new()
	qr_rect.custom_minimum_size = Vector2(230, 230)
	qr_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	qr_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	top.add_child(qr_rect)
	_qr_for = ""

	var b := Button.new()
	if OS.has_feature("web"):
		b.text = "Not available in the browser version"
		b.disabled = true
	else:
		b.text = "STOP phone server" if phone.running else "START phone server"
	b.pressed.connect(func() -> void:
		if phone.running:
			phone.stop()
		else:
			phone.start()
		_rebuild())
	left.add_child(b)
	_check(left, "Start the phone server automatically when the simulator starts", phone.autostart, func(v: bool) -> void: phone.autostart = v)
	if phone.error_text != "":
		left.add_child(_label(phone.error_text, 13, Color(1.0, 0.5, 0.4)))
	if phone.running:
		left.add_child(_label("On the phone (same Wi-Fi as this PC), scan the QR code or type:", 14, Color(0.75, 0.82, 0.9)))
		left.add_child(_label("   " + phone.url(true), 20, Color(1.0, 0.82, 0.35)))
		left.add_child(_label("Accept the certificate warning once (\"Advanced\" > \"Proceed\" / \"Show details\" > \"visit this website\"). It is this simulator's own certificate; the address only works inside your home network.", 12, Color(0.7, 0.75, 0.8)))
		left.add_child(_label("If motion still does not work: " + phone.url(false) + "  (plain HTTP, some Android browsers allow it).", 12, Color(0.7, 0.75, 0.8)))
		if phone.addresses.size() > 1:
			left.add_child(_label("Other addresses of this PC: " + ", ".join(phone.addresses.slice(1)), 12, Color(0.6, 0.65, 0.7)))
		left.add_child(_label("Windows asks once whether Godot may use the network: allow PRIVATE networks.", 12, Color(0.7, 0.75, 0.8)))
	else:
		left.add_child(_label("Start the server, then open the address on your phone. One phone can be the cyclic, a second phone the collective. Keyboard and mouse keep working for everything the phones do not control.", 13, Color(0.75, 0.82, 0.9)))

	live = _label("", 13, Color(0.85, 1.0, 0.85))
	live.custom_minimum_size = Vector2(900, 0)
	box.add_child(live)
	bars = Control.new()
	bars.custom_minimum_size = Vector2(900, 40)
	bars.draw.connect(_draw_bars)
	box.add_child(bars)
	var hb := HBoxContainer.new()
	var cal := Button.new()
	cal.text = "Set neutral now (N key in flight)"
	cal.pressed.connect(func() -> void: phone.calibrate_all())
	hb.add_child(cal)
	box.add_child(hb)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	box.add_child(cols)
	var c1 := VBoxContainer.new()
	var c2 := VBoxContainer.new()
	cols.add_child(c1)
	cols.add_child(c2)
	c1.add_child(_label("Cyclic phone", 15, Color(1.0, 0.82, 0.35)))
	_slider(c1, "Tilt for full deflection", 8.0, 45.0, 1.0, phone.cyc_range_deg, "%.0f deg", func(v: float) -> void: phone.cyc_range_deg = v)
	_slider(c1, "Centre dead zone", 0.0, 6.0, 0.25, phone.cyc_deadzone_deg, "%.2f deg", func(v: float) -> void: phone.cyc_deadzone_deg = v)
	_slider(c1, "Expo (softer centre)", 0.0, 0.9, 0.05, phone.cyc_expo, "%.2f", func(v: float) -> void: phone.cyc_expo = v)
	_check(c1, "Invert fore/aft", phone.cyc_invert_lon, func(v: bool) -> void: phone.cyc_invert_lon = v)
	_check(c1, "Invert left/right", phone.cyc_invert_lat, func(v: bool) -> void: phone.cyc_invert_lat = v)
	c2.add_child(_label("Collective phone", 15, Color(1.0, 0.82, 0.35)))
	_slider(c2, "Lever angle, down to full up", 15.0, 70.0, 1.0, phone.coll_range_deg, "%.0f deg", func(v: float) -> void: phone.coll_range_deg = v)
	_slider(c2, "Rest band at the bottom", 0.0, 8.0, 0.5, phone.coll_deadband_deg, "%.1f deg", func(v: float) -> void: phone.coll_deadband_deg = v)
	_check(c2, "Invert collective", phone.coll_invert, func(v: bool) -> void: phone.coll_invert = v)
	_check(c2, "Twist grip: rotate phone about its long axis = throttle", phone.twist_throttle, func(v: bool) -> void: phone.twist_throttle = v)
	_check(c2, "Invert twist direction", phone.twist_invert, func(v: bool) -> void: phone.twist_invert = v)
	_slider(c2, "Twist to idle", 15.0, 70.0, 1.0, phone.twist_range_deg, "%.0f deg", func(v: float) -> void: phone.twist_range_deg = v)
	_slider(box, "Smoothing (adds lag; 0 = none)", 0.0, 150.0, 5.0, phone.smoothing_ms, "%.0f ms", func(v: float) -> void: phone.smoothing_ms = v)
	box.add_child(_label("How it takes over: a phone acts at once, starting from where the control already is, so connecting, recalibrating, a reset or an instructor hand-over never makes the helicopter jump. Any difference between the phone angle and the control melts away as you move the phone (the twist-grip throttle still waits until you match it, for safety). Neutral = cyclic centred / collective fully down. If the phone disconnects, the controls stay where they were. Phone tilt is not a real cyclic: there is no stick force feel, so fly with small, smooth movements.", 12, Color(0.7, 0.75, 0.8)))

func _process(_dt: float) -> void:
	if not visible or live == null:
		return
	if phone.running and _qr_for != phone.url(true):
		_qr_for = phone.url(true)
		qr_rect.texture = _qr_texture(_qr_for)
	elif not phone.running and _qr_for != "":
		_qr_for = ""
		qr_rect.texture = null
	var t := ""
	if not phone.running:
		t = "Server stopped."
	else:
		for r in ["cyclic", "collective"]:
			if phone.roles.has(r):
				var s: Dictionary = phone.roles[r]
				var tl: Vector2 = phone.tilt_deg(r)
				var eng := false
				if r == "cyclic":
					eng = controls.phone_cyc_engaged
				else:
					eng = controls.phone_coll_engaged
				t += "%s phone: connected, %3.0f Hz (longest gap %3.0f ms), tilt fwd %+5.1f  right %+5.1f deg   %s\n" % [r.capitalize(), float(s["rate"]), float(s.get("gap_max", 0.0)), tl.x, tl.y, "IN CONTROL" if eng else "waiting: match the current %s position" % r]
			else:
				t += "%s phone: not connected\n" % r.capitalize()
	live.text = t
	bars.queue_redraw()

func _draw_bars() -> void:
	var font := ThemeDB.fallback_font
	var c = controls
	var outs := [["Cyc lat", c.cyclic_lat, true], ["Cyc lon", c.cyclic_lon, true], ["Coll", c.collective, false], ["Thr", c.throttle, false]]
	for i in outs.size():
		var x := i * 220.0
		var val: float = outs[i][1]
		bars.draw_string(font, Vector2(x, 14), outs[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.8, 0.4))
		bars.draw_rect(Rect2(Vector2(x + 60, 4), Vector2(140, 12)), Color(0.2, 0.2, 0.2))
		if outs[i][2]:
			bars.draw_rect(Rect2(Vector2(x + 130 + minf(val, 0.0) * 70.0, 4), Vector2(absf(val) * 70.0, 12)), Color(1.0, 0.7, 0.2))
		else:
			bars.draw_rect(Rect2(Vector2(x + 60, 4), Vector2(val * 140.0, 12)), Color(1.0, 0.7, 0.2))

static func _qr_texture(text: String) -> ImageTexture:
	var m: Array = QR.encode(text)
	if m.is_empty():
		return null
	var n := m.size()
	var q := 4    # quiet zone
	var img := Image.create(n + q * 2, n + q * 2, false, Image.FORMAT_L8)
	img.fill(Color.WHITE)
	for y in n:
		for x in n:
			if m[y][x]:
				img.set_pixel(x + q, y + q, Color.BLACK)
	return ImageTexture.create_from_image(img)
