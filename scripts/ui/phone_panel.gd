extends CanvasLayer
## Phone controller setup (F10): start the phone server, show the address + QR code,
## live status of each phone, calibration and sensitivity settings. Glass style (same as the pause menu).

const QR = preload("res://scripts/ui/qr.gd")
const G = preload("res://scripts/ui/glass.gd")

signal closed      # "Done" pressed (main.gd un-pauses)

var phone          # phone_server.gd
var controls
var ui_theme: Theme      # the pause menu's theme (set by main.gd)
var root: PanelContainer
var box: VBoxContainer
var status_box: VBoxContainer
var bars: Control
var qr_rect: TextureRect
var _qr_for := ""
var _role_rows := {}

func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(G.backdrop())
	root = PanelContainer.new()
	if ui_theme:
		root.theme = ui_theme
	root.add_theme_stylebox_override("panel", G.card())
	add_child(root)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 14)
	scroll.add_child(box)
	visible = false
	get_viewport().size_changed.connect(_layout)
	_layout()

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var w := minf(1040.0, vp.x - 40.0)
	var h := minf(760.0, vp.y - 40.0)
	root.position = (vp - Vector2(w, h)) * 0.5
	root.size = Vector2(w, h)

func open() -> void:
	visible = true
	_rebuild()
	_layout()

func close() -> void:
	visible = false
	phone.save_config()

func _section(parent: Node, header: String) -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if header != "":
		wrap.add_child(G.label(header.to_upper(), 12, G.TEXT3))
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", G.section())
	wrap.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	parent.add_child(wrap)
	return v

func _slider(parent: Node, text: String, vmin: float, vmax: float, step: float, value: float, fmt: String, cb: Callable) -> void:
	var h := HBoxContainer.new()
	var l := G.label(text, 14, G.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = vmin
	s.max_value = vmax
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(170, 24)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(s)
	var vl := G.label(fmt % value, 13, G.TEXT2)
	vl.custom_minimum_size = Vector2(72, 0)
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(vl)
	s.value_changed.connect(func(v: float) -> void:
		vl.text = fmt % v
		cb.call(v))
	parent.add_child(h)

func _switch(parent: Node, text: String, value: bool, cb: Callable) -> void:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = value
	c.alignment = HORIZONTAL_ALIGNMENT_LEFT
	c.toggled.connect(cb)
	parent.add_child(c)

func _rebuild() -> void:
	for c in box.get_children():
		c.queue_free()
	_role_rows.clear()
	# header
	var head := HBoxContainer.new()
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(G.label("AB206 REALSIM  ·  SETUP", 12, G.TEXT3))
	tv.add_child(G.label("Phone controller", 30, G.TEXT))
	tv.add_child(G.label("Up to three phones: cyclic, collective and pedals (feet). Settings are saved.", 13, G.TEXT2))
	head.add_child(tv)
	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(120, 44)
	done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	done.add_theme_stylebox_override("normal", G.box(G.ACCENT, 22, 0.0, 9))
	done.add_theme_stylebox_override("hover", G.box(G.ACCENT.lightened(0.12), 22, 0.0, 9))
	done.pressed.connect(func() -> void:
		close()
		closed.emit())
	head.add_child(done)
	box.add_child(head)

	# connect: server + address + QR
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	box.add_child(top)
	var left := _section(top, "Connect")
	var b := Button.new()
	if OS.has_feature("web"):
		b.text = "Not available in the browser version"
		b.disabled = true
	else:
		b.text = "Stop phone server" if phone.running else "Start phone server"
	b.pressed.connect(func() -> void:
		if phone.running:
			phone.stop()
		else:
			phone.start()
		_rebuild())
	left.add_child(b)
	_switch(left, "Start the phone server with the simulator", phone.autostart, func(v: bool) -> void: phone.autostart = v)
	if phone.error_text != "":
		left.add_child(G.label(phone.error_text, 13, G.DANGER, true))
	if phone.running:
		left.add_child(G.label("On the phone (same Wi-Fi or hotspot as this PC), scan the code or open:", 13, G.TEXT2, true))
		left.add_child(G.label(phone.url(true), 22, G.ACCENT))
		left.add_child(G.label("First time: accept the certificate warning (\"Advanced\" > \"Proceed\", or \"Show details\" > \"visit this website\" on iPhone). It is this simulator's own certificate and only works on your local network.", 12, G.TEXT3, true))
		left.add_child(G.label("Motion not working? Try " + phone.url(false) + "  (plain HTTP, some Android browsers allow it).", 12, G.TEXT3, true))
		if phone.addresses.size() > 1:
			var ah := HBoxContainer.new()
			ah.add_theme_constant_override("separation", 10)
			var al := G.label("Page does not load on the phone? This PC has %d addresses - try the next one:" % phone.addresses.size(), 12, G.TEXT3, true)
			al.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ah.add_child(al)
			var ab := Button.new()
			ab.text = "Use another address"
			ab.pressed.connect(func() -> void:
				phone.addr_pick = (phone.addr_pick + 1) % phone.addresses.size()
				_rebuild())
			ah.add_child(ab)
			left.add_child(ah)
		left.add_child(G.label("Windows asks once if Godot may use the network: allow it.", 12, G.TEXT3, true))
	else:
		left.add_child(G.label("Start the server, then open the address on your phone. Keyboard, mouse and joystick keep working for everything the phones do not control.", 13, G.TEXT2, true))
	var qr_wrap := PanelContainer.new()
	qr_wrap.add_theme_stylebox_override("panel", G.box(Color.WHITE, 18, 0.0, 10))
	qr_wrap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	qr_wrap.visible = phone.running
	qr_rect = TextureRect.new()
	qr_rect.custom_minimum_size = Vector2(210, 210)
	qr_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	qr_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	qr_wrap.add_child(qr_rect)
	top.add_child(qr_wrap)
	_qr_for = ""

	# live status
	var live := _section(box, "Live")
	status_box = VBoxContainer.new()
	status_box.add_theme_constant_override("separation", 6)
	live.add_child(status_box)
	for r in ["cyclic", "collective", "pedals"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var dot := G.label("●", 16, G.TEXT3)
		row.add_child(dot)
		var name := G.label(("Pedal" if r == "pedals" else r.capitalize()) + " phone", 15, G.TEXT)
		name.custom_minimum_size = Vector2(140, 0)
		row.add_child(name)
		var info := G.label("", 13, G.TEXT2, true)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		status_box.add_child(row)
		_role_rows[r] = [dot, info]
	bars = Control.new()
	bars.custom_minimum_size = Vector2(0, 26)
	bars.draw.connect(_draw_bars)
	live.add_child(bars)
	var cal := Button.new()
	cal.text = "Set neutral now  (N key in flight)"
	cal.pressed.connect(func() -> void: phone.calibrate_all())
	live.add_child(cal)

	# settings
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	box.add_child(cols)
	var c1 := _section(cols, "Cyclic phone")
	var c2 := _section(cols, "Collective phone")
	_slider(c1, "Tilt for full deflection", 8.0, 45.0, 1.0, phone.cyc_range_deg, "%.0f°", func(v: float) -> void: phone.cyc_range_deg = v)
	_slider(c1, "Centre dead zone", 0.0, 6.0, 0.25, phone.cyc_deadzone_deg, "%.2f°", func(v: float) -> void: phone.cyc_deadzone_deg = v)
	_slider(c1, "Expo (softer centre)", 0.0, 0.9, 0.05, phone.cyc_expo, "%.2f", func(v: float) -> void: phone.cyc_expo = v)
	_switch(c1, "Invert fore/aft", phone.cyc_invert_lon, func(v: bool) -> void: phone.cyc_invert_lon = v)
	_switch(c1, "Invert left/right", phone.cyc_invert_lat, func(v: bool) -> void: phone.cyc_invert_lat = v)
	_slider(c2, "Lever angle, down to full up", 15.0, 70.0, 1.0, phone.coll_range_deg, "%.0f°", func(v: float) -> void: phone.coll_range_deg = v)
	_slider(c2, "Rest band at the bottom", 0.0, 8.0, 0.5, phone.coll_deadband_deg, "%.1f°", func(v: float) -> void: phone.coll_deadband_deg = v)
	_switch(c2, "Invert collective", phone.coll_invert, func(v: bool) -> void: phone.coll_invert = v)
	_switch(c2, "Twist grip = throttle (rotate about long axis)", phone.twist_throttle, func(v: bool) -> void: phone.twist_throttle = v)
	_switch(c2, "Invert twist direction", phone.twist_invert, func(v: bool) -> void: phone.twist_invert = v)
	_slider(c2, "Twist to idle", 15.0, 70.0, 1.0, phone.twist_range_deg, "%.0f°", func(v: float) -> void: phone.twist_range_deg = v)
	var c3 := _section(box, "Pedal phone (feet)")
	var mh := HBoxContainer.new()
	var ml := G.label("How the phone moves", 14, G.TEXT)
	ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mh.add_child(ml)
	for i in 2:
		var mb := Button.new()
		mb.text = ["Turn  (pedal bar on a turntable)", "Rock  (tilt left / right)"][i]
		mb.toggle_mode = true
		mb.button_pressed = phone.ped_mode == i
		mb.pressed.connect(func() -> void:
			phone.ped_mode = i
			phone.calibrate("pedals")
			_rebuild())
		mh.add_child(mb)
	c3.add_child(mh)
	_slider(c3, "Turn / tilt for full pedal", 5.0, 45.0, 1.0, phone.ped_range_deg, "%.0f°", func(v: float) -> void: phone.ped_range_deg = v)
	_slider(c3, "Centre dead zone", 0.0, 6.0, 0.25, phone.ped_deadzone_deg, "%.2f°", func(v: float) -> void: phone.ped_deadzone_deg = v)
	_switch(c3, "Invert pedals", phone.ped_invert, func(v: bool) -> void: phone.ped_invert = v)
	c3.add_child(G.label("Turn: lay the phone flat, screen up, on the pedal bar (the DIY pedals turn on a lazy susan). Right foot forward = right pedal. It uses the phone's gyro heading, which can drift slowly: if the pedals no longer centre, press N with your feet level. Rock: lay the phone on a board that rocks left/right under your feet; right side down = right pedal. No drift.", 12, G.TEXT3, true))
	var adv := _section(box, "Advanced")
	_slider(adv, "Smoothing (adds lag; 0 = none)", 0.0, 150.0, 5.0, phone.smoothing_ms, "%.0f ms", func(v: float) -> void: phone.smoothing_ms = v)
	box.add_child(G.label("How it takes over: a phone controls its lever from the moment it connects. The helicopter does not jump: any difference between the phone and the current control position fades out as you move the phone. Neutral = cyclic centred / collective fully down / pedals centred. If a phone drops, the control stays where it was and the phone reconnects by itself. Keep the phone page open and the screen on. If this PC uses the phone's hotspot, keep that phone's screen on too. Phone tilt is not a real cyclic (no stick force), so fly with small, smooth movements.", 12, G.TEXT3, true))
	box.add_child(G.label("F10 or Esc  close", 11, G.TEXT3))

func _process(_dt: float) -> void:
	if not visible or status_box == null:
		return
	if phone.running and _qr_for != phone.url(true):
		_qr_for = phone.url(true)
		qr_rect.texture = _qr_texture(_qr_for)
	elif not phone.running and _qr_for != "":
		_qr_for = ""
		qr_rect.texture = null
	var now := Time.get_ticks_msec() / 1000.0
	for r in _role_rows:
		var dot: Label = _role_rows[r][0]
		var info: Label = _role_rows[r][1]
		var col := G.TEXT3
		var t := ""
		if not phone.running:
			t = "server stopped"
		elif phone.roles.has(r):
			var s: Dictionary = phone.roles[r]
			var tl: Vector2 = phone.tilt_deg(r)
			var eng: bool = controls.phone_engaged(r)
			col = G.GOOD if eng else G.WARN
			var mv := "tilt fwd %+.1f°  right %+.1f°" % [tl.x, tl.y]
			if r == "pedals":
				mv = "%s %+.1f° (right +)" % ["turned" if phone.ped_mode == 0 else "rocked", phone.pedal_deg()]
				if phone.ped_mode == 0 and not s.get("has_yaw", false):
					mv += "  -  this phone sends no heading: use Rock mode"
			t = "%s  ·  %.0f Hz  ·  longest gap %.0f ms  ·  %s" % ["IN CONTROL" if eng else "connected (instructor has it)", float(s["rate"]), float(s.get("gap_max", 0.0)), mv]
		elif phone.lost_at.has(r):
			col = G.DANGER
			t = "signal lost %.0f s ago - waiting for the phone to reconnect (keep its page open and screen on)" % (now - float(phone.lost_at[r]))
		else:
			t = "not connected"
		if phone.running and int(phone.drops.get(r, 0)) > 0:
			t += "   ·   drops this session: %d" % int(phone.drops[r])
		dot.add_theme_color_override("font_color", col)
		info.text = t
	bars.queue_redraw()

func _draw_bars() -> void:
	var font: Font = ui_theme.default_font if ui_theme and ui_theme.default_font else ThemeDB.fallback_font
	var c = controls
	var outs := [["Cyc lat", c.cyclic_lat, true], ["Cyc lon", c.cyclic_lon, true], ["Coll", c.collective, false], ["Pedal", c.pedal, true], ["Thr", c.throttle, false]]
	var w := bars.size.x / outs.size()
	for i in outs.size():
		var x := i * w
		bars.draw_string(font, Vector2(x, 17), outs[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, G.TEXT2)
		G.meter(bars, Rect2(Vector2(x + 58, 8), Vector2(w - 78, 10)), float(outs[i][1]), outs[i][2])

static func _qr_texture(text: String) -> ImageTexture:
	var m: Array = QR.encode(text)
	if m.is_empty():
		return null
	var n := m.size()
	var q := 2    # quiet zone (the white card adds more)
	var img := Image.create(n + q * 2, n + q * 2, false, Image.FORMAT_L8)
	img.fill(Color.WHITE)
	for y in n:
		for x in n:
			if m[y][x]:
				img.set_pixel(x + q, y + q, Color.BLACK)
	return ImageTexture.create_from_image(img)
