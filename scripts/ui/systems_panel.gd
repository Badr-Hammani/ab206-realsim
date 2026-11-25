extends CanvasLayer
## Cockpit systems + checklist panel (J). The simulation keeps running while it is open:
## left = the switches you would reach for in the 206 (battery, generator, fuel valve, boost,
## hydraulics, anti-ice, lights, radios, frictions, caution test, starter, throttle closed/idle,
## governor beep) and the engine readouts + caution panel; right = the checklists. Items marked
## AUTO tick themselves when the cockpit is really in that state; the others you confirm.

signal closed

const G = preload("res://scripts/ui/glass.gd")

var main
var systems
var checklist
var ui_theme: Theme

var _left: PanelContainer
var _right: PanelContainer
var _sw := {}                     # key -> Button
var _gauges: Label
var _caut: GridContainer
var _caut_lbl := {}
var _list_pick: OptionButton
var _items_box: VBoxContainer
var _items_scroll: ScrollContainer
var _src: Label
var _objective: Label
var _built_for := ""
var _rows: Array = []
var _confirm_btn: Button

const SWITCHES := [
	["battery", "BATTERY"], ["generator", "GENERATOR"],
	["fuel_valve", "FUEL VALVE"], ["boost", "FUEL BOOST (breakers)"],
	["hydraulics", "HYDRAULICS"], ["anti_ice", "ENG ANTI-ICE"],
	["landing_light", "LANDING LIGHT"], ["radios", "RADIOS (switch only)"],
	["friction", "FRICTIONS (coll + throttle)"], ["throttle_closed", "THROTTLE CLOSED"],
]

func _ready() -> void:
	layer = 8
	visible = false
	_build()

func _btn(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 30)
	b.add_theme_font_size_override("font_size", 13)
	return b

func _dock(left: bool, w: float) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := G.box(Color(0.08, 0.10, 0.13, 0.88), 16, 0.12, 12)
	p.add_theme_stylebox_override("panel", sb)
	if ui_theme:
		p.theme = ui_theme
	p.anchor_top = 0.0
	p.anchor_bottom = 1.0
	p.offset_top = 10
	p.offset_bottom = -40
	if left:
		p.anchor_left = 0.0
		p.anchor_right = 0.0
		p.offset_left = 10
		p.offset_right = 10 + w
	else:
		p.anchor_left = 1.0
		p.anchor_right = 1.0
		p.offset_left = -10 - w
		p.offset_right = -10
	add_child(p)
	return p

func _build() -> void:
	_left = _dock(true, 372)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	_left.add_child(lv)
	lv.add_child(G.label("COCKPIT SYSTEMS", 18, G.TEXT))
	lv.add_child(G.label("J close  ·  sim keeps running  ·  I = starter (hold)  ·  [ ] = governor RPM", 11, G.TEXT3, true))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 5)
	lv.add_child(grid)
	for s in SWITCHES:
		var b := _btn(s[1])
		b.custom_minimum_size = Vector2(170, 30)
		b.pressed.connect(_toggle.bind(s[0]))
		grid.add_child(b)
		_sw[s[0]] = b
	var st := _btn("STARTER  (hold)")
	st.custom_minimum_size = Vector2(170, 34)
	st.button_down.connect(func() -> void: systems.starter_btn = true)
	st.button_up.connect(func() -> void: systems.starter_btn = false)
	grid.add_child(st)
	_sw["starter"] = st
	var ct := _btn("CAUTION TEST (hold)")
	ct.custom_minimum_size = Vector2(170, 34)
	ct.button_down.connect(func() -> void: systems.caution_test = true)
	ct.button_up.connect(func() -> void: systems.caution_test = false)
	grid.add_child(ct)
	_sw["caution_test"] = ct
	var gm := _btn("GOV RPM  DECR  [")
	gm.pressed.connect(func() -> void: main.beep_gov(-1.0))
	grid.add_child(gm)
	var gp := _btn("GOV RPM  INCR  ]")
	gp.pressed.connect(func() -> void: main.beep_gov(1.0))
	grid.add_child(gp)
	var oh := _btn("OVERHEAD BREAKERS  (O)")
	oh.custom_minimum_size = Vector2(170, 30)
	oh.pressed.connect(func() -> void: main.overhead.toggle())
	grid.add_child(oh)
	lv.add_child(G.label("ENGINE", 12, G.TEXT3))
	_gauges = G.label("", 13, Color(0.75, 1.0, 0.8))
	_gauges.add_theme_font_override("font", _mono())
	lv.add_child(_gauges)
	lv.add_child(G.label("CAUTION PANEL", 12, G.TEXT3))
	_caut = GridContainer.new()
	_caut.columns = 2
	_caut.add_theme_constant_override("h_separation", 6)
	_caut.add_theme_constant_override("v_separation", 4)
	lv.add_child(_caut)
	for n in systems.CAUTION_NAMES:
		var pc := PanelContainer.new()
		pc.custom_minimum_size = Vector2(170, 24)
		var l := G.label(n, 12, Color(0.5, 0.4, 0.3))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pc.add_child(l)
		_caut.add_child(pc)
		_caut_lbl[n] = [pc, l]
	lv.add_child(G.label("Panel numbers marked SIMULATION in the docs (TOT curve, pressures, fuel burn) are estimates, not Bell data.", 10, G.TEXT3, true))

	_right = _dock(false, 440)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	_right.add_child(rv)
	rv.add_child(G.label("CHECKLIST", 18, G.TEXT))
	_objective = G.label("", 12, Color(0.75, 0.95, 1.0), true)
	rv.add_child(_objective)
	_list_pick = OptionButton.new()
	_list_pick.focus_mode = Control.FOCUS_NONE
	for l in checklist.lists:
		_list_pick.add_item(("EMERGENCY - " if l["kind"] == "emergency" else "") + str(l["title"]))
	_list_pick.item_selected.connect(func(i: int) -> void:
		checklist.open_list(str(checklist.lists[i]["id"]))
		_rebuild_items())
	rv.add_child(_list_pick)
	_src = G.label("", 10, G.TEXT3, true)
	rv.add_child(_src)
	_items_scroll = ScrollContainer.new()
	_items_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_items_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(_items_scroll)
	_items_box = VBoxContainer.new()
	_items_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items_box.add_theme_constant_override("separation", 2)
	_items_scroll.add_child(_items_box)
	var hb := HBoxContainer.new()
	rv.add_child(hb)
	_confirm_btn = _btn("Checked  (Enter)")
	_confirm_btn.pressed.connect(func() -> void: checklist.confirm())
	hb.add_child(_confirm_btn)
	var rs := _btn("Restart list")
	rs.pressed.connect(func() -> void:
		checklist.start_list(checklist.list_id if checklist.active() else "start")
		_rebuild_items())
	hb.add_child(rs)
	rv.add_child(G.label("AUTO = ticks itself from the cockpit state.  Others: look / do it, then Enter.", 10, G.TEXT3, true))

func _mono() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Courier New", "monospace"])
	return f

func _toggle(key: String) -> void:
	if key == "boost":
		# 206B-3: no boost switch, the two FUEL BOOST breakers on the overhead
		var put_in: bool = not (systems.cb_in("FUEL BOOST FWD") and systems.cb_in("FUEL BOOST AFT"))
		systems.pull_breaker("FUEL BOOST FWD", not put_in)
		systems.pull_breaker("FUEL BOOST AFT", not put_in)
		return
	if key == "throttle_closed":
		main.set_throttle_closed(not systems.throttle_closed)
		return
	if key == "friction":
		main.set_friction(not systems.friction)
		return
	systems.set(key, not bool(systems.get(key)))

func open() -> void:
	visible = true
	if not checklist.active():
		checklist.start_list("start")
	_rebuild_items()

func close() -> void:
	visible = false
	systems.starter_btn = false
	systems.caution_test = false
	closed.emit()

func _rebuild_items() -> void:
	for c in _items_box.get_children():
		c.queue_free()
	_rows.clear()
	if not checklist.active():
		return
	var l: Dictionary = checklist.current_list()
	for i in checklist.lists.size():
		if checklist.lists[i]["id"] == checklist.list_id:
			_list_pick.select(i)
	_src.text = "Source: " + str(l.get("source", "")) + ("\nNOTE: " + str(l["note"]) if l.has("note") else "")
	for it in l["items"]:
		if it.has("heading"):
			var h := G.label(str(it["heading"]).to_upper(), 12, G.TEXT3)
			_items_box.add_child(h)
			_rows.append(h)
			continue
		var row := Label.new()
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.custom_minimum_size = Vector2(400, 0)
		row.add_theme_font_size_override("font_size", 13)
		var txt := "%s  -  %s" % [it["item"], it["action"]]
		if it.has("auto"):
			txt += "   [AUTO]"
		if it.has("note"):
			txt += "\n      " + str(it["note"])
		row.text = txt
		_items_box.add_child(row)
		_rows.append(row)
	_built_for = checklist.list_id

func _process(_dt: float) -> void:
	if not visible or systems == null:
		return
	if _built_for != checklist.list_id:
		_rebuild_items()
	for s in SWITCHES:
		var on: bool = bool(systems.get(s[0])) if s[0] != "boost" else (systems.cb_in("FUEL BOOST FWD") and systems.cb_in("FUEL BOOST AFT"))
		var b: Button = _sw[s[0]]
		b.text = "%s   %s" % [s[1], "ON" if on else "OFF"] if s[0] != "throttle_closed" else ("THROTTLE   CLOSED" if on else "THROTTLE   IDLE / OPEN")
		b.modulate = Color(0.6, 1.0, 0.65) if on else Color(1, 1, 1, 0.8)
	(_sw["starter"] as Button).modulate = Color(1.0, 0.85, 0.4) if systems.fdm.starter else Color(1, 1, 1, 0.8)
	var f = systems.fdm
	_gauges.text = "N1 %5.1f %%    TOT %4.0f C %s\nNR %5.1f %%    N2  %5.1f %%   TQ %4.0f %%\nENG OIL %3.0f psi   TRANS OIL %2.0f psi\nFUEL %3.0f lb  %2.0f psi   GOV %3.0f %%   OAT %3.0f C\nBUS %s   GEN %s   throttle %3.0f %%%s" % [
		f.n1, systems.tot, "HOT!" if systems.tot > 810.0 else "", f.nr_pct(), f.n2_pct(), maxf(f.torque_pct, 0.0),
		systems.eng_oil_psi, systems.xmsn_oil_psi, systems.fuel_lb, systems.fuel_psi, f.gov_set_pct, systems.oat_c,
		"ON" if systems.bus_powered else "OFF", "ON LINE" if systems.gen_online else "off", f.throttle * 100.0,
		("\nSTART peak TOT %.0f C" % systems.tot_peak) if f.starter or f.starting else ""]
	for n in systems.CAUTION_NAMES:
		var lit: bool = systems.cautions[n]
		var pc: PanelContainer = _caut_lbl[n][0]
		var l: Label = _caut_lbl[n][1]
		var red: bool = n in ["ENG OUT", "ROTOR LOW RPM", "TOT"]
		pc.add_theme_stylebox_override("panel", G.box((Color(0.85, 0.12, 0.08) if red else Color(0.95, 0.7, 0.1)) if lit else Color(0.15, 0.12, 0.1), 4, 0.15, 2))
		l.add_theme_color_override("font_color", Color(1, 1, 1) if lit else Color(0.45, 0.38, 0.3))
	# checklist rows
	_objective.text = main.lessons.objective if main.lessons.active() else ""
	var idx := 0
	for i in checklist.items().size():
		if i >= _rows.size():
			break
		var it: Dictionary = checklist.items()[i]
		if it.has("heading"):
			continue
		var r: Label = _rows[i]
		var st: String = checklist.state[i] if i < checklist.state.size() else ""
		if st == "auto" or st == "confirmed":
			r.add_theme_color_override("font_color", G.GOOD)
		elif st == "skipped":
			r.add_theme_color_override("font_color", G.WARN)
		elif i == checklist.cur:
			r.add_theme_color_override("font_color", Color(1, 1, 1))
		else:
			r.add_theme_color_override("font_color", G.TEXT3)
		var mark := "✓ " if st in ["auto", "confirmed"] else ("~ " if st == "skipped" else ("▶ " if i == checklist.cur else "   "))
		if not r.text.begins_with(mark):
			r.text = mark + r.text.trim_prefix("✓ ").trim_prefix("~ ").trim_prefix("▶ ").trim_prefix("   ")
		idx += 1
	_confirm_btn.text = "Checked  (Enter)" if checklist.current_is_manual() else "Skip (Enter)"
