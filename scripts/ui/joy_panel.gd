extends CanvasLayer
## Joystick / HOTAS setup (F8): live raw axes, assign an axis to each flight control
## by moving it, invert, dead zone, and range calibration (min/max recorded live).

var controls
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
	root = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.07, 0.95)
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
	root.offset_left = -420
	root.offset_right = 420
	root.offset_top = -320
	root.offset_bottom = 320
	add_child(root)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	root.add_child(box)
	visible = false

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
	var t := Label.new()
	t.text = "JOYSTICK SETUP  (F8 or Esc to close - settings are saved)"
	t.add_theme_font_size_override("font_size", 17)
	box.add_child(t)
	var pads := Input.get_connected_joypads()
	var dl := Label.new()
	if pads.is_empty():
		dl.text = "No joystick detected. Plug it in - it appears here automatically."
	else:
		var names := []
		for d in pads:
			names.append("#%d %s" % [d, Input.get_joy_name(d)])
		dl.text = "Devices: " + ", ".join(names)
	box.add_child(dl)
	raw_view = Control.new()
	raw_view.custom_minimum_size = Vector2(800, 120)
	raw_view.draw.connect(_draw_raw)
	box.add_child(raw_view)
	for fn in controls.FUNCS:
		var h := HBoxContainer.new()
		var l := Label.new()
		l.text = fn.capitalize()
		l.custom_minimum_size = Vector2(110, 0)
		h.add_child(l)
		var bl := Label.new()
		bl.custom_minimum_size = Vector2(240, 0)
		if controls.bindings.has(fn):
			var b: Dictionary = controls.bindings[fn]
			bl.text = "dev %d axis %d  range %.2f..%.2f%s" % [b["device"], b["axis"], b.get("min", -1.0), b.get("max", 1.0), "  INV" if b.get("invert", false) else ""]
		else:
			bl.text = "keyboard / mouse"
		if _assigning == fn:
			bl.text = ">>> move the axis now <<<"
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
		dz.custom_minimum_size = Vector2(110, 20)
		dz.value = controls.bindings[fn].get("deadzone", 0.03) if controls.bindings.has(fn) else 0.03
		dz.editable = controls.bindings.has(fn)
		dz.tooltip_text = "Dead zone"
		dz.value_changed.connect(func(v: float) -> void:
			if controls.bindings.has(fn):
				controls.bindings[fn]["deadzone"] = v)
		h.add_child(dz)
		box.add_child(h)
	var cal := Button.new()
	cal.text = "STOP calibration (save ranges)" if _calibrating else "Calibrate ranges: press, move every assigned axis to both limits, press again"
	cal.pressed.connect(_toggle_cal)
	box.add_child(cal)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(800, 0)
	_info.text = "Collective and throttle use the full axis range (0..1). Cyclic and pedals are centred with a dead zone. If a direction is backwards, press Invert."
	box.add_child(_info)

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
	var font := ThemeDB.fallback_font
	var y := 0.0
	for d in Input.get_connected_joypads():
		for a in 8:
			var val := Input.get_joy_axis(d, a)
			var x := (a % 4) * 200.0
			var yy := y + int(a / 4) * 26.0
			raw_view.draw_rect(Rect2(Vector2(x + 70, yy + 4), Vector2(120, 12)), Color(0.2, 0.2, 0.2))
			raw_view.draw_rect(Rect2(Vector2(x + 130 + minf(val, 0.0) * 60.0, yy + 4), Vector2(absf(val) * 60.0, 12)), Color(0.3, 0.8, 1.0))
			raw_view.draw_string(font, Vector2(x, yy + 15), "d%d ax%d" % [d, a], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		y += 56.0
	if Input.get_connected_joypads().is_empty():
		raw_view.draw_string(font, Vector2(0, 20), "(no devices)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.7, 0.7))
	# mapped outputs
	var c = controls
	var outs := [["Cyc lat", c.cyclic_lat, true], ["Cyc lon", c.cyclic_lon, true], ["Coll", c.collective, false], ["Pedal", c.pedal, true], ["Thr", c.throttle, false]]
	for i in outs.size():
		var x := i * 160.0
		var yy := 100.0
		var val: float = outs[i][1]
		raw_view.draw_string(font, Vector2(x, yy + 12), outs[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.8, 0.4))
		raw_view.draw_rect(Rect2(Vector2(x + 55, yy + 2), Vector2(90, 12)), Color(0.2, 0.2, 0.2))
		if outs[i][2]:
			raw_view.draw_rect(Rect2(Vector2(x + 100 + minf(val, 0.0) * 45.0, yy + 2), Vector2(absf(val) * 45.0, 12)), Color(1.0, 0.7, 0.2))
		else:
			raw_view.draw_rect(Rect2(Vector2(x + 55, yy + 2), Vector2(val * 90.0, 12)), Color(1.0, 0.7, 0.2))
