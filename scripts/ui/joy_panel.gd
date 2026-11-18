extends CanvasLayer
## Joystick / HOTAS setup (F8): live raw axes, assign an axis to each flight control
## by moving it, invert, dead zone, and range calibration (min/max recorded live).

const G = preload("res://scripts/ui/glass.gd")

signal closed      # "Done" pressed (main.gd un-pauses)

var controls
var ui_theme: Theme      # the pause menu's theme (set by main.gd)
var root: PanelContainer
var box: VBoxContainer
var raw_view: Control
var _assigning := ""
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
	var w := minf(980.0, vp.x - 40.0)
	var h := minf(720.0, vp.y - 40.0)
	root.position = (vp - Vector2(w, h)) * 0.5
	root.size = Vector2(w, h)

func open() -> void:
	visible = true
	_rebuild()

func close() -> void:
	visible = false
	_assigning = ""
	_calibrating = false
	controls.save_config()

func _rebuild() -> void:
	for c in box.get_children():
		c.queue_free()
	var head := HBoxContainer.new()
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(G.label("AB206 REALSIM  ·  SETUP", 12, G.TEXT3))
	tv.add_child(G.label("Joystick / HOTAS", 30, G.TEXT))
	tv.add_child(G.label("Assign an axis to each control by moving it. Settings are saved.", 13, G.TEXT2))
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
	var dl := G.label("", 13, G.TEXT2, true)
	if pads.is_empty():
		dl.text = "No joystick detected. Plug it in - it appears here automatically."
	else:
		var names := []
		for d in pads:
			names.append("#%d %s" % [d, Input.get_joy_name(d)])
		dl.text = "Devices: " + ", ".join(names)
	box.add_child(dl)
	var rv_wrap := PanelContainer.new()
	rv_wrap.add_theme_stylebox_override("panel", G.section())
	raw_view = Control.new()
	raw_view.custom_minimum_size = Vector2(0, maxf(56.0 * pads.size(), 30.0) + 36.0)
	raw_view.draw.connect(_draw_raw)
	rv_wrap.add_child(raw_view)
	box.add_child(G.label("LIVE AXES", 12, G.TEXT3))
	box.add_child(rv_wrap)
	box.add_child(G.label("CONTROLS", 12, G.TEXT3))
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
		l.custom_minimum_size = Vector2(110, 0)
		h.add_child(l)
		var bl := G.label("", 13, G.TEXT2)
		bl.custom_minimum_size = Vector2(250, 0)
		bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if controls.bindings.has(fn):
			var b: Dictionary = controls.bindings[fn]
			bl.text = "dev %d axis %d  range %.2f..%.2f%s" % [b["device"], b["axis"], b.get("min", -1.0), b.get("max", 1.0), "  INV" if b.get("invert", false) else ""]
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
		dz.custom_minimum_size = Vector2(110, 24)
		dz.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dz.value = controls.bindings[fn].get("deadzone", 0.03) if controls.bindings.has(fn) else 0.03
		dz.editable = controls.bindings.has(fn)
		dz.tooltip_text = "Dead zone"
		dz.value_changed.connect(func(v: float) -> void:
			if controls.bindings.has(fn):
				controls.bindings[fn]["deadzone"] = v)
		h.add_child(dz)
		fbox.add_child(h)
	var cal := Button.new()
	cal.text = "STOP calibration (save ranges)" if _calibrating else "Calibrate ranges: press, move every assigned axis to both limits, press again"
	cal.pressed.connect(_toggle_cal)
	box.add_child(cal)
	_info = G.label("", 12, G.TEXT3, true)
	_info.text = "Collective and throttle use the full axis range (0..1). Cyclic and pedals are centred with a dead zone (slider on each row). If a direction is backwards, press Invert."
	box.add_child(_info)
	box.add_child(G.label("F8 or Esc  close", 11, G.TEXT3))

func _start_assign(fn: String) -> void:
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
			var raw := Input.get_joy_axis(int(b["device"]), int(b["axis"]))
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
				controls.bindings[_assigning] = {"device": key.x, "axis": key.y, "invert": false, "min": -1.0, "max": 1.0, "deadzone": 0.03}
				_assigning = ""
				_rebuild()
				return
	if _calibrating:
		for fn in controls.bindings:
			var b: Dictionary = controls.bindings[fn]
			var raw := Input.get_joy_axis(int(b["device"]), int(b["axis"]))
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
		y += 56.0
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
