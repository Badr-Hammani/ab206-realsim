extends CanvasLayer
## Heads-up display: telemetry overlay (F6), control positions, instructor messages,
## status line, help (F1) and the 2D copy of the instrument panel (Tab).

const G = preload("res://scripts/ui/glass.gd")

## F1 help: [key, what it does] rows, grouped.
const HELP_GROUPS := [
	["Flight controls (keyboard + mouse)", [
		["Mouse", "Cyclic - stays where you leave it.   X centre   M mouse cyclic on/off"],
		["Arrow keys", "Cyclic nudges (spring back)"],
		["W / S, wheel", "Collective up / down (Shift = faster) - lever stays where you leave it"],
		["A / D", "Pedals (spring back to trim)   Q / E move pedal trim"],
		["R / F", "Throttle open / close (full open = governor holds 100% N2)"],
		["H", "Training assist: off / damping / attitude hold / hover hold (not on the real aircraft)"],
		["Y", "Training speed 100 / 75 / 50 %"],
	]],
	["View and sim", [
		["V", "Cockpit / chase / free camera   right mouse = look around   C recentre"],
		["Z", "Instrument view: look down and zoom onto the panel (Z again = look outside)"],
		["Tab", "2D instrument panel     I J K L U O move free camera"],
		["Esc", "Menu: lessons, aircraft, weather, settings     P pause"],
		["F2  F3  F4  F5", "Reset on pad / hover 5 m / cruise 80 kt / autorotation at 2,500 ft"],
		["F6  F7", "Telemetry overlay / graphics preset"],
		["F8", "Joystick setup"],
		["F10   N", "Phone controller (tilt a phone = cyclic / collective)   N set phone neutral"],
		["F9  F11  F12", "Instructor messages / fullscreen / screenshot"],
		["G   B   T", "Hover guide / outside sight gates / take all controls"],
		["K   Shift+K   + / -", "Map: small / big (pin points, draw zones) / off   pin where you are   zoom the small map"],
	]],
]
const FIRST_FLIGHT := "First flight: on the pad, raise the collective (W) slowly until the skids get light, hold left pedal (A or Q trim) against the torque, keep the cyclic centred, and lift into a 1 m hover. Small, early corrections."

var telemetry: Label
var status: Label
var msg_panel: PanelContainer
var msg_label: Label
var help: PanelContainer
var panel_holder: Control
var panel2d: Control
var ctrl_view: Control
var show_telemetry := true
var landing_label: Label
var lesson_panel: PanelContainer
var lesson_label: Label
var landing_time := 0.0
var guide_view: Control
var _guide := {}

func _label(parent: Node, size := 14, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)
	return l

func _panel_style(alpha := 0.6) -> StyleBoxFlat:
	var sb := G.box(Color(0.09, 0.11, 0.15, alpha), 14, 0.14, 12)
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	return sb

func build(panel_scene_script: Script) -> void:
	layer = 5
	telemetry = _label(self, 13, Color(0.85, 1.0, 0.85))
	telemetry.position = Vector2(12, 10)
	status = _label(self, 14, Color(1, 1, 1))
	status.anchor_left = 0.0
	status.anchor_top = 1.0
	status.anchor_bottom = 1.0
	status.position = Vector2(12, -28)
	status.offset_top = -30
	status.offset_left = 12
	msg_panel = PanelContainer.new()
	msg_panel.add_theme_stylebox_override("panel", _panel_style(0.7))
	msg_panel.anchor_left = 0.5
	msg_panel.anchor_right = 0.5
	msg_panel.offset_left = -360
	msg_panel.offset_right = 360
	msg_panel.offset_top = 14
	add_child(msg_panel)
	msg_label = _label(msg_panel, 15, Color(1.0, 0.92, 0.6))
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.custom_minimum_size = Vector2(696, 0)
	msg_panel.visible = false
	landing_label = _label(self, 26, Color(1, 1, 1))
	landing_label.anchor_left = 0.5
	landing_label.anchor_right = 0.5
	landing_label.anchor_top = 0.35
	landing_label.offset_left = -300
	landing_label.offset_right = 300
	landing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lesson_panel = PanelContainer.new()
	lesson_panel.add_theme_stylebox_override("panel", _panel_style(0.65))
	lesson_panel.anchor_left = 1.0
	lesson_panel.anchor_right = 1.0
	lesson_panel.offset_left = -470
	lesson_panel.offset_right = -14
	lesson_panel.offset_top = 150
	add_child(lesson_panel)
	lesson_label = _label(lesson_panel, 14, Color(0.75, 0.95, 1.0))
	lesson_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lesson_label.custom_minimum_size = Vector2(430, 0)
	lesson_panel.visible = false
	help = PanelContainer.new()
	var hsb := G.card()
	hsb.bg_color = Color(0.08, 0.10, 0.13, 0.93)
	help.add_theme_stylebox_override("panel", hsb)
	help.anchor_left = 0.5
	help.anchor_top = 0.5
	help.anchor_right = 0.5
	help.anchor_bottom = 0.5
	help.offset_left = -500
	help.offset_top = -330
	help.offset_right = 500
	help.offset_bottom = 330
	help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help.grow_vertical = Control.GROW_DIRECTION_BOTH
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 8)
	help.add_child(hv)
	hv.add_child(G.label("AB206 REALSIM  ·  BELL 206B-3  ·  educational simulation, not a training device", 12, G.TEXT3))
	hv.add_child(G.label("Keys and controls", 28, G.TEXT))
	hv.add_child(Control.new())
	for grp in HELP_GROUPS:
		hv.add_child(G.label(String(grp[0]).to_upper(), 12, G.TEXT3))
		var sec := PanelContainer.new()
		sec.add_theme_stylebox_override("panel", G.box(Color(1, 1, 1, 0.06), 14, 0.07, 10))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 4)
		sec.add_child(grid)
		for row in grp[1]:
			var k := G.label(row[0], 14, G.ACCENT.lightened(0.25))
			k.custom_minimum_size = Vector2(150, 0)
			grid.add_child(k)
			grid.add_child(G.label(row[1], 14, G.TEXT))
		hv.add_child(sec)
	hv.add_child(G.label(FIRST_FLIGHT, 13, G.TEXT2, true))
	hv.add_child(G.label("F1  close", 11, G.TEXT3))
	add_child(help)
	help.visible = false
	# 2D instrument panel (bottom centre), scaled to fit
	panel_holder = Control.new()
	panel_holder.anchor_left = 0.5
	panel_holder.anchor_right = 0.5
	panel_holder.anchor_top = 1.0
	panel_holder.anchor_bottom = 1.0
	add_child(panel_holder)
	panel2d = Control.new()
	panel2d.set_script(panel_scene_script)
	panel_holder.add_child(panel2d)
	panel2d.scale = Vector2(0.62, 0.62)
	panel2d.position = Vector2(-310, -262)
	# control position indicator (bottom right)
	ctrl_view = Control.new()
	ctrl_view.anchor_left = 1.0
	ctrl_view.anchor_right = 1.0
	ctrl_view.anchor_top = 1.0
	ctrl_view.anchor_bottom = 1.0
	ctrl_view.position = Vector2(-250, -170)
	ctrl_view.size = Vector2(240, 160)
	ctrl_view.draw.connect(_draw_controls.bind(ctrl_view))
	add_child(ctrl_view)
	# hover guide (bottom left, above the status line)
	guide_view = Control.new()
	guide_view.position = Vector2(14, 250)
	guide_view.size = Vector2(290, 260)
	guide_view.draw.connect(_draw_guide.bind(guide_view))
	add_child(guide_view)
	guide_view.visible = false

var _ghost := {}
var _stick := Vector2.ZERO
var _stick_mode := false

## Ghost = the instructor's suggested position for the controls you fly (hollow markers).
## stick_mode: assists 2/3 active, so your stick (orange) and the real cyclic (grey) differ.
func set_ghost(g: Dictionary, s_lon: float, s_lat: float, stick_mode: bool) -> void:
	_ghost = g
	_stick = Vector2(s_lat, s_lon)
	_stick_mode = stick_mode

var _ctrl := {"lon": 0.0, "lat": 0.0, "coll": 0.0, "ped": 0.0, "thr": 1.0, "trim": 0.0}

func set_controls(lon: float, lat: float, coll: float, ped: float, thr: float, ped_trim: float) -> void:
	_ctrl = {"lon": lon, "lat": lat, "coll": coll, "ped": ped, "thr": thr, "trim": ped_trim}
	ctrl_view.queue_redraw()

func _draw_controls(c: Control) -> void:
	var font := ThemeDB.fallback_font
	var bg := Color(0, 0, 0, 0.45)
	# cyclic box
	var box := Rect2(Vector2(0, 0), Vector2(110, 110))
	c.draw_rect(box, bg)
	c.draw_rect(box, Color(0.7, 0.7, 0.7, 0.8), false, 1.0)
	c.draw_line(Vector2(55, 0), Vector2(55, 110), Color(1, 1, 1, 0.25))
	c.draw_line(Vector2(0, 55), Vector2(110, 55), Color(1, 1, 1, 0.25))
	var p := Vector2(55 + _ctrl["lat"] * 52, 55 - _ctrl["lon"] * 52)
	if _stick_mode:
		c.draw_circle(p, 4, Color(0.75, 0.75, 0.75, 0.8))          # real cyclic (assist output)
		p = Vector2(55 + _stick.x * 52, 55 - _stick.y * 52)        # your stick
	if _ghost.has("lon"):
		var gp := Vector2(55 + clampf(float(_ghost["lat"]), -1.0, 1.0) * 52, 55 - clampf(float(_ghost["lon"]), -1.0, 1.0) * 52)
		c.draw_arc(gp, 9, 0, TAU, 20, Color(0.4, 1.0, 0.5, 0.95), 2.0)
		c.draw_line(p, gp, Color(0.4, 1.0, 0.5, 0.35), 1.0)
	c.draw_circle(p, 6, Color(1.0, 0.7, 0.2))
	c.draw_string(font, Vector2(0, 126), "CYCLIC", HORIZONTAL_ALIGNMENT_CENTER, 110, 12, Color.WHITE)
	# collective bar
	var cb := Rect2(Vector2(122, 0), Vector2(22, 110))
	c.draw_rect(cb, bg)
	c.draw_rect(Rect2(Vector2(122, 110 - 110 * _ctrl["coll"]), Vector2(22, 110 * _ctrl["coll"])), Color(0.3, 0.8, 1.0, 0.85))
	if _ghost.has("coll"):
		var gy := 110 - 110 * clampf(float(_ghost["coll"]), 0.0, 1.0)
		c.draw_rect(Rect2(Vector2(118, gy - 2), Vector2(30, 4)), Color(0.4, 1.0, 0.5, 0.95), false, 2.0)
	c.draw_string(font, Vector2(112, 126), "COLL", HORIZONTAL_ALIGNMENT_CENTER, 42, 12, Color.WHITE)
	# throttle bar
	var tb := Rect2(Vector2(156, 0), Vector2(22, 110))
	c.draw_rect(tb, bg)
	c.draw_rect(Rect2(Vector2(156, 110 - 110 * _ctrl["thr"]), Vector2(22, 110 * _ctrl["thr"])), Color(0.4, 1.0, 0.4, 0.85))
	c.draw_string(font, Vector2(146, 126), "THR", HORIZONTAL_ALIGNMENT_CENTER, 42, 12, Color.WHITE)
	# pedals
	var pb := Rect2(Vector2(0, 136), Vector2(178, 16))
	c.draw_rect(pb, bg)
	c.draw_line(Vector2(89, 136), Vector2(89, 152), Color(1, 1, 1, 0.4))
	c.draw_line(Vector2(89 + _ctrl["trim"] * 87, 134), Vector2(89 + _ctrl["trim"] * 87, 154), Color(0.6, 0.6, 1.0), 2)
	if _ghost.has("ped"):
		c.draw_arc(Vector2(89 + clampf(float(_ghost["ped"]), -1.0, 1.0) * 87, 144), 9, 0, TAU, 20, Color(0.4, 1.0, 0.5, 0.95), 2.0)
	c.draw_circle(Vector2(89 + _ctrl["ped"] * 87, 144), 6, Color(1.0, 0.7, 0.2))
	if not _ghost.is_empty():
		c.draw_string(font, Vector2(0, -6), "green ring = instructor's suggestion", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 1.0, 0.5))
	c.draw_string(font, Vector2(184, 149), "PEDAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

func set_guide(g: Dictionary) -> void:
	_guide = g
	guide_view.visible = not g.is_empty()
	if guide_view.visible:
		guide_view.queue_redraw()

## Hover guide: top-down view in the aircraft's own frame (nose up). Rings = 1.2 m (ACS 4 ft)
## and 3 m around the target spot; arrow = your movement over the ground; bar = skid height.
func _draw_guide(c: Control) -> void:
	var g := _guide
	if g.is_empty():
		return
	var font := ThemeDB.fallback_font
	c.draw_style_box(G.box(Color(0.09, 0.11, 0.15, 0.55), 14, 0.14, 0), Rect2(Vector2(-6, -6), Vector2(300, 272)))
	var ctr := Vector2(110, 115)
	var R := 100.0
	var px_m := R / 4.0                       # 4 m to the edge
	c.draw_circle(ctr, R + 4.0, Color(0, 0, 0, 0.45))
	c.draw_arc(ctr, R, 0, TAU, 48, Color(1, 1, 1, 0.25), 1.0)
	c.draw_line(ctr - Vector2(R, 0), ctr + Vector2(R, 0), Color(1, 1, 1, 0.12))
	c.draw_line(ctr - Vector2(0, R), ctr + Vector2(0, R), Color(1, 1, 1, 0.12))
	var spot := ctr
	if g.has("rel"):
		var rel: Vector2 = g["rel"]            # (forward, right) from the aircraft to the spot
		spot = ctr + Vector2(rel.y, -rel.x) * px_m
		var far := (spot - ctr).length() > R
		if far:
			spot = ctr + (spot - ctr).normalized() * R
		c.draw_arc(spot, float(g.get("pass_pos", 3.0)) * px_m, 0, TAU, 40, Color(1.0, 0.75, 0.2, 0.7), 1.5)
		c.draw_arc(spot, float(g.get("tol_pos", 1.2)) * px_m, 0, TAU, 32, Color(0.4, 1.0, 0.5, 0.9), 2.0)
		c.draw_line(spot - Vector2(6, 0), spot + Vector2(6, 0), Color(1, 0.9, 0.2), 2.0)
		c.draw_line(spot - Vector2(0, 6), spot + Vector2(0, 6), Color(1, 0.9, 0.2), 2.0)
		if far:
			c.draw_string(font, spot + Vector2(-20, -10), "%.0f m" % rel.length(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.9, 0.2))
	# aircraft symbol (nose up)
	c.draw_line(ctr + Vector2(0, -10), ctr + Vector2(0, 16), Color.WHITE, 2.0)
	c.draw_line(ctr + Vector2(-8, 0), ctr + Vector2(8, 0), Color.WHITE, 2.0)
	c.draw_line(ctr + Vector2(-4, 16), ctr + Vector2(4, 16), Color.WHITE, 2.0)
	# ground-speed vector: 1 m/s = 30 px
	var v: Vector2 = g.get("vel", Vector2.ZERO)
	var vv := Vector2(v.y, -v.x) * 30.0
	if vv.length() > R:
		vv = vv.normalized() * R
	if vv.length() > 3.0:
		c.draw_line(ctr, ctr + vv, Color(0.3, 0.85, 1.0), 3.0)
		c.draw_circle(ctr + vv, 4.0, Color(0.3, 0.85, 1.0))
	# heading error tick on the top of the ring
	var hdg_t: float = g.get("hdg", NAN)
	if not is_nan(hdg_t):
		var he := deg_to_rad(wrapf(hdg_t - float(g["hdg_now"]), -180.0, 180.0))
		var tol := deg_to_rad(float(g.get("tol_hdg", 10.0)))
		c.draw_arc(ctr, R + 2.0, -PI / 2.0 - tol, -PI / 2.0 + tol, 10, Color(0.4, 1.0, 0.5, 0.9), 4.0)
		var tip := ctr + Vector2(sin(he), -cos(he)) * (R + 2.0)
		c.draw_circle(tip, 5.0, Color(1, 0.9, 0.2))
	# yaw rate
	c.draw_string(font, Vector2(4, 236), "yaw %+3.0f deg/s   GS %.1f m/s" % [float(g.get("yaw_rate", 0.0)), v.length()], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.9, 1.0))
	# skid height bar 0..4 m
	var bx := Rect2(Vector2(226, 15), Vector2(20, 200))
	c.draw_rect(bx, Color(0, 0, 0, 0.45))
	var m2px := 200.0 / 4.0
	var ht: float = g.get("height", NAN)
	if not is_nan(ht):
		var tl: float = g.get("tol_h", 0.5)
		var top := 215.0 - (ht + tl) * m2px
		c.draw_rect(Rect2(Vector2(226, top), Vector2(20, 2.0 * tl * m2px)), Color(0.4, 1.0, 0.5, 0.35))
		c.draw_line(Vector2(222, 215.0 - ht * m2px), Vector2(250, 215.0 - ht * m2px), Color(0.4, 1.0, 0.5), 1.5)
	var agl := clampf(float(g.get("agl", 0.0)), 0.0, 4.0)
	var yy := 215.0 - agl * m2px
	c.draw_line(Vector2(220, yy), Vector2(252, yy), Color(1, 0.9, 0.2), 3.0)
	var vs: float = g.get("vs", 0.0)
	if absf(vs) > 0.05:
		c.draw_line(Vector2(256, yy), Vector2(256, yy - clampf(vs, -2.0, 2.0) * 40.0), Color(0.3, 0.85, 1.0), 3.0)
	c.draw_string(font, Vector2(220, 232), "%.1f m" % float(g.get("agl", 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	var own: String = g.get("owner", "")
	if own != "":
		c.draw_string(font, Vector2(4, 254), own, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.85, 0.5))
	c.draw_string(font, Vector2(4, 10), "HOVER GUIDE (training aid, G)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.8))

func set_lesson(text: String) -> void:
	lesson_panel.visible = text != ""
	if text != "":
		lesson_label.text = text

func show_landing(text: String, col: Color) -> void:
	landing_label.text = text
	landing_label.add_theme_color_override("font_color", col)
	landing_time = 5.0

func update_hud(dt: float, tele_text: String, status_text: String, instructor_msg: String, msg_visible: bool) -> void:
	telemetry.visible = show_telemetry
	if show_telemetry:
		telemetry.text = tele_text
	status.text = status_text
	msg_panel.visible = msg_visible and instructor_msg != ""
	msg_label.text = instructor_msg
	landing_time = maxf(landing_time - dt, 0.0)
	landing_label.visible = landing_time > 0.0
