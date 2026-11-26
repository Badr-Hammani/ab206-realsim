extends CanvasLayer
## Joystick / HOTAS setup (F8): live raw axes & buttons, assign an axis to each flight
## control by moving it, press-to-assign joystick buttons, 8-way POV hat camera look,
## invert, dead zone, expo, range calibration, and Thrustmaster T.Flight Stick X preset.

const G = preload("res://scripts/ui/glass.gd")

signal closed      # "Done" pressed (main.gd un-pauses)

var controls
var assist               # training_assist.gd (set by main.gd)
var ui_theme: Theme      # the pause menu's theme (set by main.gd)
var root: PanelContainer
var box: VBoxContainer
var raw_view: Control
var _assigning := ""
var _assigning_btn := ""
var _baseline := {}
var _calibrating := false
var _info: Label

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
	box.add_theme_constant_override("separation", 12)
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
	controls.btn_capture_paused = true
	_rebuild()

func close() -> void:
	visible = false
	_assigning = ""
	_assigning_btn = ""
	_calibrating = false
	controls.btn_capture_paused = false
	controls.save_config()

func _input(event: InputEvent) -> void:
	if not visible or _assigning_btn == "":
		return
	if event is InputEventJoypadButton and event.pressed:
		controls.btn_bindings[_assigning_btn] = {
			"device": event.device,
			"button": event.button_index,
			"dev_name": Input.get_joy_name(event.device),
		}
		_assigning_btn = ""
		get_viewport().set_input_as_handled()
		_rebuild()

func _rebuild() -> void:
	for c in box.get_children():
		c.queue_free()
	var head := HBoxContainer.new()
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(G.label("AB206 REALSIM  ·  SETUP", 12, G.TEXT3))
	tv.add_child(G.label("Joystick / HOTAS", 30, G.TEXT))
	tv.add_child(G.label("Assign axes by moving them, assign buttons by pressing them. Settings are saved.", 13, G.TEXT2))
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

	var pads := Input.get_connected_joypads()
	var dev_row := HBoxContainer.new()
	dev_row.add_theme_constant_override("separation", 10)
	var dl := G.label("", 13, G.TEXT2, true)
	dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if pads.is_empty():
		dl.text = "No joystick detected. Plug it in - it appears here automatically."
	else:
		var names := []
		for d in pads:
			names.append("#%d %s" % [d, Input.get_joy_name(d)])
		dl.text = "Devices: " + ", ".join(names)
	dev_row.add_child(dl)
	if not pads.is_empty():
		var preset_btn := Button.new()
		preset_btn.text = "Apply T.Flight Stick X preset"
		preset_btn.pressed.connect(func() -> void:
			controls.apply_tflight_stick_x_preset()
			_rebuild())
		dev_row.add_child(preset_btn)
	box.add_child(dev_row)

	# live axes & buttons
	var rv_wrap := PanelContainer.new()
	rv_wrap.add_theme_stylebox_override("panel", G.section())
	raw_view = Control.new()
	raw_view.custom_minimum_size = Vector2(0, maxf(86.0 * pads.size(), 30.0) + 38.0)
	raw_view.draw.connect(_draw_raw)
	rv_wrap.add_child(raw_view)
	box.add_child(G.label("LIVE AXES & BUTTONS", 12, G.TEXT3))
	box.add_child(rv_wrap)

	# flight axes
	box.add_child(G.label("FLIGHT AXES", 12, G.TEXT3))
	var fwrap := PanelContainer.new()
	fwrap.add_theme_stylebox_override("panel", G.section())
	var fbox := VBoxContainer.new()
	fbox.add_theme_constant_override("separation", 8)
	fwrap.add_child(fbox)
	box.add_child(fwrap)
	for fn in controls.FUNCS:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var l := G.label(fn.capitalize(), 15, G.TEXT)
		l.custom_minimum_size = Vector2(106, 0)
		h.add_child(l)
		var bl := G.label("", 13, G.TEXT2)
		bl.custom_minimum_size = Vector2(220, 0)
		bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if controls.bindings.has(fn):
			var b: Dictionary = controls.bindings[fn]
			bl.text = "dev %d ax %d  [%.2f..%.2f]%s" % [b["device"], b["axis"], b.get("min", -1.0), b.get("max", 1.0), "  INV" if b.get("invert", false) else ""]
		else:
			bl.text = "keyboard / mouse"
		if _assigning == fn:
			bl.text = "Move the axis now..."
			bl.add_theme_color_override("font_color", G.ACCENT)
		h.add_child(bl)
		var ba := Button.new()
		ba.text = "Assign"
		ba.pressed.connect(func() -> void: _start_assign(fn))
		h.add_child(ba)
		var bi := Button.new()
		bi.text = "Invert"
		bi.disabled = not controls.bindings.has(fn)
		bi.pressed.connect(func() -> void:
			controls.bindings[fn]["invert"] = not controls.bindings[fn].get("invert", false)
			_rebuild())
		h.add_child(bi)
		var bc := Button.new()
		bc.text = "Clear"
		bc.disabled = not controls.bindings.has(fn)
		bc.pressed.connect(func() -> void:
			controls.bindings.erase(fn)
			_rebuild())
		h.add_child(bc)
		var dz := HSlider.new()
		dz.min_value = 0.0
		dz.max_value = 0.2
		dz.step = 0.01
		dz.custom_minimum_size = Vector2(92, 24)
		dz.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dz.value = controls.bindings[fn].get("deadzone", 0.03) if controls.bindings.has(fn) else 0.03
		dz.editable = controls.bindings.has(fn)
		dz.tooltip_text = "Dead zone"
		dz.value_changed.connect(func(v: float) -> void:
			if controls.bindings.has(fn):
				controls.bindings[fn]["deadzone"] = v)
		h.add_child(dz)
		if fn != "collective" and fn != "throttle":
			var ex := HSlider.new()
			ex.min_value = 0.0
			ex.max_value = 0.8
			ex.step = 0.05
			ex.custom_minimum_size = Vector2(92, 24)
			ex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			ex.value = controls.bindings[fn].get("expo", 0.0) if controls.bindings.has(fn) else 0.0
			ex.editable = controls.bindings.has(fn)
			ex.tooltip_text = "Expo (softer centre)"
			ex.value_changed.connect(func(v: float) -> void:
				if controls.bindings.has(fn):
					controls.bindings[fn]["expo"] = v)
			h.add_child(ex)
		else:
			var sp := Control.new()
			sp.custom_minimum_size = Vector2(92, 1)
			h.add_child(sp)
		fbox.add_child(h)
	var cal := Button.new()
	cal.text = "STOP calibration (save ranges)" if _calibrating else "Calibrate ranges: press, move every assigned axis to both limits, press again"
	cal.pressed.connect(_toggle_cal)
	fbox.add_child(cal)
	var sm_row := HBoxContainer.new()
	var sm_lbl := G.label("Control smoothing (hydraulic feel; 0 = raw)", 14, G.TEXT)
	sm_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sm_row.add_child(sm_lbl)
	var sm_sl := HSlider.new()
	sm_sl.min_value = 0.0
	sm_sl.max_value = 140.0
	sm_sl.step = 5.0
	sm_sl.value = controls.joy_smooth_ms
	sm_sl.custom_minimum_size = Vector2(160, 24)
	sm_sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sm_val := G.label("%.0f ms" % controls.joy_smooth_ms, 13, G.TEXT2)
	sm_val.custom_minimum_size = Vector2(58, 0)
	sm_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sm_sl.value_changed.connect(func(v: float) -> void:
		controls.joy_smooth_ms = v
		sm_val.text = "%.0f ms" % v)
	sm_row.add_child(sm_sl)
	sm_row.add_child(sm_val)
	fbox.add_child(sm_row)
	if assist != null:
		var ap_chk := CheckButton.new()
		ap_chk.text = "Auto-pedals (heading hold & torque cancel while learning to hover)"
		ap_chk.button_pressed = assist.auto_pedal
		ap_chk.toggled.connect(func(v: bool) -> void: assist.auto_pedal = v)
		fbox.add_child(ap_chk)
	_info = G.label("Collective and throttle use the full axis range (0..1). Cyclic and pedals are centred with Dead zone (left slider) and Expo (right slider).", 12, G.TEXT3, true)
	fbox.add_child(_info)

	# POV hat
	box.add_child(G.label("POV HAT (PANORAMIC VIEW)", 12, G.TEXT3))
	var pwrap := PanelContainer.new()
	pwrap.add_theme_stylebox_override("panel", G.section())
	var pbox := VBoxContainer.new()
	pbox.add_theme_constant_override("separation", 8)
	pwrap.add_child(pbox)
	box.add_child(pwrap)
	var pov_chk := CheckButton.new()
	pov_chk.text = "POV hat pans the camera (Cockpit / Chase / Free)"
	pov_chk.button_pressed = controls.pov_hat_look
	pov_chk.toggled.connect(func(v: bool) -> void: controls.pov_hat_look = v)
	pbox.add_child(pov_chk)
	var ps_row := HBoxContainer.new()
	var ps_lbl := G.label("POV look speed", 14, G.TEXT)
	ps_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ps_row.add_child(ps_lbl)
	var ps_sl := HSlider.new()
	ps_sl.min_value = 0.4
	ps_sl.max_value = 2.5
	ps_sl.step = 0.1
	ps_sl.value = controls.pov_look_speed
	ps_sl.custom_minimum_size = Vector2(160, 24)
	ps_sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ps_val := G.label("%.1fx" % controls.pov_look_speed, 13, G.TEXT2)
	ps_val.custom_minimum_size = Vector2(54, 0)
	ps_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ps_sl.value_changed.connect(func(v: float) -> void:
		controls.pov_look_speed = v
		ps_val.text = "%.1fx" % v)
	ps_row.add_child(ps_sl)
	ps_row.add_child(ps_val)
	pbox.add_child(ps_row)

	# buttons
	var bhead := HBoxContainer.new()
	var bh_lbl := G.label("JOYSTICK BUTTONS", 12, G.TEXT3)
	bh_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bhead.add_child(bh_lbl)
	var clear_all_b := Button.new()
	clear_all_b.text = "Clear all buttons"
	clear_all_b.disabled = controls.btn_bindings.is_empty()
	clear_all_b.pressed.connect(func() -> void:
		controls.btn_bindings.clear()
		_rebuild())
	bhead.add_child(clear_all_b)
	box.add_child(bhead)

	var bwrap := PanelContainer.new()
	bwrap.add_theme_stylebox_override("panel", G.section())
	var bbox := VBoxContainer.new()
	bbox.add_theme_constant_override("separation", 6)
	bwrap.add_child(bbox)
	box.add_child(bwrap)
	for act in controls.BTN_ACTIONS:
		var id: String = act[0]
		var label_text: String = act[1]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var l := G.label(label_text, 14, G.TEXT)
		l.custom_minimum_size = Vector2(220, 0)
		h.add_child(l)
		var bl := G.label("", 13, G.TEXT2)
		bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if controls.btn_bindings.has(id):
			var b: Dictionary = controls.btn_bindings[id]
			bl.text = "dev %d  %s" % [int(b["device"]), controls.button_name(int(b["button"]))]
		else:
			bl.text = "unassigned"
			bl.add_theme_color_override("font_color", G.TEXT3)
		if _assigning_btn == id:
			bl.text = "Press any joystick button now..."
			bl.add_theme_color_override("font_color", G.ACCENT)
		h.add_child(bl)
		var ba := Button.new()
		ba.text = "Assign"
		ba.pressed.connect(func() -> void:
			_assigning = ""
			_assigning_btn = id
			_rebuild())
		h.add_child(ba)
		var bc := Button.new()
		bc.text = "Clear"
		bc.disabled = not controls.btn_bindings.has(id)
		bc.pressed.connect(func() -> void:
			controls.btn_bindings.erase(id)
			_rebuild())
		h.add_child(bc)
		bbox.add_child(h)

	box.add_child(G.label("F8 or Esc  close", 11, G.TEXT3))

func _start_assign(fn: String) -> void:
	_assigning_btn = ""
	_assigning = fn
	_baseline.clear()
	for d in Input.get_connected_joypads():
		for a in 8:
			_baseline[Vector2i(d, a)] = Input.get_joy_axis(d, a)
	_rebuild()

func _toggle_cal() -> void:
	_calibrating = not _calibrating
	if _calibrating:
		for fn in controls.bindings:
			var b: Dictionary = controls.bindings[fn]
			var dev: int = controls._resolve_device(b)
			var raw := Input.get_joy_axis(dev, int(b["axis"])) if dev >= 0 else 0.0
			b["min"] = raw
			b["max"] = raw + 0.001
	_rebuild()

func _process(_dt: float) -> void:
	if not visible:
		return
	controls.update(0.0)
	if raw_view:
		raw_view.queue_redraw()
	if _assigning != "":
		for key in _baseline:
			var val := Input.get_joy_axis(key.x, key.y)
			if absf(val - float(_baseline[key])) > 0.5:
				var prev_expo := 0.25 if (_assigning == "cyclic_lat" or _assigning == "cyclic_lon" or _assigning == "pedal") else 0.0
				controls.bindings[_assigning] = {
					"device": key.x,
					"axis": key.y,
					"invert": false,
					"min": -1.0,
					"max": 1.0,
					"deadzone": 0.05,
					"expo": prev_expo,
					"dev_name": Input.get_joy_name(key.x),
				}
				_assigning = ""
				_rebuild()
				return
	if _calibrating:
		for fn in controls.bindings:
			var b: Dictionary = controls.bindings[fn]
			var dev: int = controls._resolve_device(b)
			if dev >= 0:
				var raw := Input.get_joy_axis(dev, int(b["axis"]))
				b["min"] = minf(float(b["min"]), raw)
				b["max"] = maxf(float(b["max"]), raw)

func _draw_raw() -> void:
	var font: Font = ui_theme.default_font if ui_theme and ui_theme.default_font else ThemeDB.fallback_font
	var cw := raw_view.size.x / 4.0
	var y := 0.0
	for d in Input.get_connected_joypads():
		for a in 8:
			var val := Input.get_joy_axis(d, a)
			var x := (a % 4) * cw
			var yy := y + int(a / 4) * 26.0
			raw_view.draw_string(font, Vector2(x, yy + 15), "d%d ax%d" % [d, a], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, G.TEXT2)
			G.meter(raw_view, Rect2(Vector2(x + 62, yy + 6), Vector2(cw - 80, 10)), val, true)
		# live button pills (B1..B12 + HAT U/D/L/R)
		var by := y + 54.0
		var items := []
		for bi in 11:
			items.append([bi, "B%d" % (bi + 1)])
		items.append([JOY_BUTTON_DPAD_UP, "HU"])
		items.append([JOY_BUTTON_DPAD_DOWN, "HD"])
		items.append([JOY_BUTTON_DPAD_LEFT, "HL"])
		items.append([JOY_BUTTON_DPAD_RIGHT, "HR"])
		var pw := minf((raw_view.size.x - 4.0) / float(items.size()), 56.0)
		for i in items.size():
			var idx: int = items[i][0]
			var lbl: String = items[i][1]
			var pressed := Input.is_joy_button_pressed(d, idx)
			var r := Rect2(Vector2(i * pw, by), Vector2(pw - 4.0, 22.0))
			raw_view.draw_rect(r, G.ACCENT if pressed else Color(1, 1, 1, 0.08), true)
			raw_view.draw_string(font, Vector2(r.position.x + 6.0, r.position.y + 15.0), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.1, 0.08, 0.02) if pressed else G.TEXT2)
		y += 86.0
	if Input.get_connected_joypads().is_empty():
		raw_view.draw_string(font, Vector2(0, 20), "No device", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, G.TEXT3)
	# mapped outputs
	var c = controls
	var outs := [["Cyc lat", c.cyclic_lat, true], ["Cyc lon", c.cyclic_lon, true], ["Coll", c.collective, false], ["Pedal", c.pedal, true], ["Thr", c.throttle, false]]
	var ow := raw_view.size.x / outs.size()
	for i in outs.size():
		var x := i * ow
		var yy := maxf(y, 30.0) + 10.0
		raw_view.draw_string(font, Vector2(x, yy + 14), outs[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, G.TEXT)
		G.meter(raw_view, Rect2(Vector2(x + 58, yy + 5), Vector2(ow - 72, 10)), float(outs[i][1]), outs[i][2])
