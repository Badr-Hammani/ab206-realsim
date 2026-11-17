extends CanvasLayer
## Pause menu (Esc) - clean "glass" design: a frosted panel over the blurred sim, four tabs
## (Fly, Lessons, Weather, Settings), grouped cards with one setting per row, segmented
## controls for choices and switches for on/off. Every control changes the running simulation.

signal action(name: String)

const Lessons = preload("res://scripts/core/lessons.gd")

const ACCENT := Color(0.24, 0.56, 1.0)          # iOS-like blue
const TEXT := Color(0.97, 0.98, 1.0)
const TEXT2 := Color(0.97, 0.98, 1.0, 0.62)     # secondary text
const TEXT3 := Color(0.97, 0.98, 1.0, 0.42)
const GOOD := Color(0.35, 0.86, 0.47)
const DANGER := Color(1.0, 0.38, 0.35)
const TABS := ["Fly", "Lessons", "Weather", "Settings"]

const BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float lod = 3.2;
uniform vec4 tint : source_color = vec4(0.05, 0.07, 0.10, 0.45);
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, lod).rgb;
	COLOR = vec4(mix(c, tint.rgb, tint.a), 1.0);
}
"""

var main                       # reference to main.gd
var root: PanelContainer       # the glass card
var rows: VBoxContainer        # content of the current tab
var tab := 0
var _backdrop: ColorRect
var _tabbar: HBoxContainer
var _subtitle: Label
var _scroll: ScrollContainer
var _theme: Theme

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_theme = _make_theme()
	# blurred, darkened sim behind the panel
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BLUR_SHADER
	sm.shader = sh
	_backdrop.material = sm
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)
	# glass panel
	root = PanelContainer.new()
	root.theme = _theme
	root.add_theme_stylebox_override("panel", _glass(Color(0.11, 0.13, 0.17, 0.72), 26, 0.16, 28))
	root.set_anchors_preset(Control.PRESET_CENTER)
	add_child(root)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	root.add_child(col)
	# header: title + resume
	var head := HBoxContainer.new()
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(_label("AB206 REALSIM  ·  BELL 206B-3", 12, TEXT3))
	tv.add_child(_label("Paused", 30, TEXT))
	_subtitle = _label("", 13, TEXT2)
	tv.add_child(_subtitle)
	head.add_child(tv)
	var resume := _pill("Resume", true)
	resume.custom_minimum_size = Vector2(130, 44)
	resume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	resume.pressed.connect(func() -> void: action.emit("resume"))
	head.add_child(resume)
	col.add_child(head)
	# segmented tab bar
	var tb_wrap := PanelContainer.new()
	tb_wrap.add_theme_stylebox_override("panel", _glass(Color(1, 1, 1, 0.07), 12, 0.0, 3))
	_tabbar = HBoxContainer.new()
	_tabbar.add_theme_constant_override("separation", 3)
	tb_wrap.add_child(_tabbar)
	col.add_child(tb_wrap)
	# content
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 14)
	_scroll.add_child(rows)
	col.add_child(_label("Esc  resume      F1  all keys      Educational simulation - not an approved training device.", 11, TEXT3))
	visible = false
	get_viewport().size_changed.connect(_layout)

# ------------------------------------------------------------------ styling
func _glass(bg: Color, radius: int, border_alpha: float, pad: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 10
	if border_alpha > 0.0:
		sb.set_border_width_all(1)
		sb.border_color = Color(1, 1, 1, border_alpha)
	sb.set_content_margin_all(pad)
	sb.anti_aliasing = true
	return sb

func _btn_box(bg: Color, radius := 10, pad_h := 14, pad_v := 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 8
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	return sb

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)
	# buttons: soft glass chips
	t.set_stylebox("normal", "Button", _btn_box(Color(1, 1, 1, 0.08)))
	t.set_stylebox("hover", "Button", _btn_box(Color(1, 1, 1, 0.15)))
	t.set_stylebox("pressed", "Button", _btn_box(Color(ACCENT, 0.9)))
	t.set_stylebox("hover_pressed", "Button", _btn_box(Color(ACCENT, 1.0)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", _btn_box(Color(1, 1, 1, 0.03)))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "Button", TEXT)
	t.set_color("font_disabled_color", "Button", TEXT3)
	# switches (CheckButton): iOS-style track and knob
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		t.set_stylebox(st, "CheckButton", StyleBoxEmpty.new())
	t.set_icon("checked", "CheckButton", _switch_icon(true))
	t.set_icon("unchecked", "CheckButton", _switch_icon(false))
	t.set_icon("checked_mirrored", "CheckButton", _switch_icon(true))
	t.set_icon("unchecked_mirrored", "CheckButton", _switch_icon(false))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "CheckButton", TEXT)
	# sliders: thin track, accent fill, white round knob
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.16)
	track.set_corner_radius_all(3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill: StyleBoxFlat = track.duplicate()
	fill.bg_color = ACCENT
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var knob := _circle_icon(22, Color.WHITE)
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", knob)
	# thin scroll bar
	var sbar := StyleBoxFlat.new()
	sbar.bg_color = Color(1, 1, 1, 0.0)
	var sgrab := StyleBoxFlat.new()
	sgrab.bg_color = Color(1, 1, 1, 0.25)
	sgrab.set_corner_radius_all(3)
	sgrab.content_margin_left = 3
	sgrab.content_margin_right = 3
	t.set_stylebox("scroll", "VScrollBar", sbar)
	t.set_stylebox("grabber", "VScrollBar", sgrab)
	t.set_stylebox("grabber_highlight", "VScrollBar", sgrab)
	t.set_stylebox("grabber_pressed", "VScrollBar", sgrab)
	return t

func _circle_icon(d: int, c: Color) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var r := d * 0.5
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - 1.0 - dist + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(c, c.a * a))
	return ImageTexture.create_from_image(img)

## iOS-style switch: rounded track (green when on) with a white knob.
func _switch_icon(on: bool) -> ImageTexture:
	var w := 46
	var h := 28
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var tc := GOOD if on else Color(1, 1, 1, 0.22)
	var kr := h * 0.5 - 3.0
	var kc := Vector2(w - h * 0.5, h * 0.5) if on else Vector2(h * 0.5, h * 0.5)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(p.x, h * 0.5, w - h * 0.5)
			var dt := (p - Vector2(cx, h * 0.5)).length()
			var ta := clampf(h * 0.5 - dt + 0.5, 0.0, 1.0)
			var col := Color(tc, tc.a * ta)
			var dk := (p - kc).length()
			var ka := clampf(kr - dk + 0.5, 0.0, 1.0)
			col = col.blend(Color(1, 1, 1, ka))
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

func _label(text: String, size := 15, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _pill(text: String, primary := false, danger := false) -> Button:
	var b := Button.new()
	b.text = text
	if primary:
		b.add_theme_stylebox_override("normal", _btn_box(ACCENT, 22, 18, 9))
		b.add_theme_stylebox_override("hover", _btn_box(ACCENT.lightened(0.12), 22, 18, 9))
		b.add_theme_stylebox_override("pressed", _btn_box(ACCENT.darkened(0.15), 22, 18, 9))
		b.add_theme_font_size_override("font_size", 16)
	if danger:
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(c, DANGER)
	return b

# --------------------------------------------------------------- building blocks
## A card (grouped list like iOS settings) with an optional small caps header above it.
func _card(header := "", footer := "") -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)
	if header != "":
		wrap.add_child(_label(header.to_upper(), 12, TEXT3))
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _glass(Color(1, 1, 1, 0.06), 16, 0.07, 14))
	wrap.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	if footer != "":
		var fl := _label(footer, 12, TEXT3)
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wrap.add_child(fl)
	rows.add_child(wrap)
	return v

func _sep(card: VBoxContainer) -> void:
	var s := ColorRect.new()
	s.color = Color(1, 1, 1, 0.07)
	s.custom_minimum_size = Vector2(0, 1)
	card.add_child(s)

## One row: title (+ small grey subtitle) on the left, a control on the right.
func _row(card: VBoxContainer, title: String, sub: String, right: Control) -> void:
	if card.get_child_count() > 0:
		_sep(card)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 1)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(_label(title, 15, TEXT))
	if sub != "":
		var sl := _label(sub, 12, TEXT2)
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(sl)
	h.add_child(tv)
	if right != null:
		right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(right)
	card.add_child(h)

func _switch(card: VBoxContainer, title: String, sub: String, value: bool, cb: Callable) -> void:
	var c := CheckButton.new()
	c.button_pressed = value
	c.toggled.connect(cb)
	_row(card, title, sub, c)

## Segmented control: one choice of several; the selected one is filled with the accent.
func _segmented(items: Array, selected: int, cb: Callable, min_w := 0) -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel", _glass(Color(1, 1, 1, 0.07), 10, 0.0, 2))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	wrap.add_child(h)
	for i in items.size():
		var b := Button.new()
		b.text = str(items[i])
		var bg := ACCENT if i == selected else Color(1, 1, 1, 0.0)
		b.add_theme_stylebox_override("normal", _btn_box(bg, 8, 12, 6))
		b.add_theme_stylebox_override("hover", _btn_box(ACCENT.lightened(0.1) if i == selected else Color(1, 1, 1, 0.10), 8, 12, 6))
		b.add_theme_font_size_override("font_size", 14)
		if min_w > 0:
			b.custom_minimum_size = Vector2(min_w, 0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i
		b.pressed.connect(func() -> void: cb.call(idx))
		h.add_child(b)
	return wrap

func _slider_row(card: VBoxContainer, title: String, vmin: float, vmax: float, step: float, value: float, fmt: String, cb: Callable) -> void:
	if card.get_child_count() > 0:
		_sep(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var h := HBoxContainer.new()
	var tl := _label(title, 15, TEXT)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tl)
	var vl := _label(fmt % value, 15, TEXT2)
	h.add_child(vl)
	v.add_child(h)
	var s := HSlider.new()
	s.min_value = vmin
	s.max_value = vmax
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(0, 26)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(x: float) -> void:
		vl.text = fmt % x
		cb.call(x))
	v.add_child(s)
	card.add_child(v)

## Big tile button (Fly tab quick actions).
func _tile(grid: GridContainer, icon: String, title: String, sub: String, act: String, primary := false) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 74)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg := Color(ACCENT, 0.85) if primary else Color(1, 1, 1, 0.07)
	b.add_theme_stylebox_override("normal", _btn_box(bg, 16, 14, 10))
	b.add_theme_stylebox_override("hover", _btn_box(bg.lightened(0.15) if primary else Color(1, 1, 1, 0.14), 16, 14, 10))
	b.add_theme_stylebox_override("pressed", _btn_box(ACCENT, 16, 14, 10))
	b.pressed.connect(func() -> void: action.emit(act))
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 14
	v.offset_top = 10
	v.offset_right = -10
	v.offset_bottom = -8
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 0)
	var t1 := _label(icon + "  " + title, 16, TEXT)
	t1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t1)
	var t2 := _label(sub, 12, TEXT if primary else TEXT2)
	t2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t2)
	b.add_child(v)
	grid.add_child(b)

func _chip(text: String, color: Color) -> Control:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _btn_box(Color(color, 0.18), 9, 9, 3))
	pc.add_child(_label(text, 12, color))
	return pc

# ------------------------------------------------------------------- tabs
func build() -> void:
	for c in rows.get_children():
		c.queue_free()
	for c in _tabbar.get_children():
		c.queue_free()
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 36)
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_stylebox_override("normal", _btn_box(Color(1, 1, 1, 0.16) if i == tab else Color(1, 1, 1, 0.0), 9, 12, 6))
		b.add_theme_stylebox_override("hover", _btn_box(Color(1, 1, 1, 0.18) if i == tab else Color(1, 1, 1, 0.07), 9, 12, 6))
		b.add_theme_stylebox_override("pressed", _btn_box(Color(1, 1, 1, 0.22), 9, 12, 6))
		if i != tab:
			b.add_theme_color_override("font_color", TEXT2)
		var idx := i
		b.pressed.connect(func() -> void:
			tab = idx
			build())
		_tabbar.add_child(b)
	var L = main.lessons
	_subtitle.text = ("In lesson: " + L.lesson_title()) if L.active() else ("Training assist: " + main.assist.name())
	match tab:
		0: _build_fly()
		1: _build_lessons()
		2: _build_weather()
		3: _build_settings()
	_scroll.scroll_vertical = 0

func show_tab(i: int) -> void:
	tab = clampi(i, 0, TABS.size() - 1)
	build()

func _build_fly() -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	rows.add_child(grid)
	_tile(grid, "▶", "Resume", "Back to flying", "resume", true)
	_tile(grid, "⌂", "On the pad", "Engine running, skids down", "reset_pad")
	_tile(grid, "◎", "Hover 5 m", "Trimmed hover", "reset_hover")
	_tile(grid, "➤", "Cruise 80 kt", "Level flight", "reset_cruise")
	_tile(grid, "↓", "Autorotation", "Engine to idle at 2,500 ft", "reset_auto")
	if main.lessons.active():
		_tile(grid, "■", "Stop lesson", main.lessons.lesson_title().substr(0, 26), "lesson_stop")
	else:
		_tile(grid, "★", "Lessons", "Hover, take-off, landing", "tab_lessons")
	_assist_card()
	var c := _card("Aircraft")
	_slider_row(c, "Gross weight  (max 1,451 kg)", 850.0, 1451.0, 5.0, main.fdm.mass, "%.0f kg", func(v: float) -> void: main.set_weight(v))

const ASSIST_ITEMS := ["Off", "1  Damping", "2  Attitude", "3  Hover hold"]
const ASSIST_DESC := ["The real 206: nothing holds it for you.", "Wobbles damped - you still find the stick position.", "Stick sets the attitude; centre it and it levels itself.", "Stick sets ground speed; centre it and it stops and holds the spot."]

func _assist_card() -> void:
	var c := _card("Training assist  (H)", "Not on the real 206: learning aids you take off one at a time. " +
		("Automatic: each lesson picks the level and lowers it after a score of 80+." if main.lessons.auto_assist else "Your choice stays as you set it, in every lesson."))
	_row(c, "Assist level", ASSIST_DESC[main.assist.level], null)
	c.add_child(_segmented(ASSIST_ITEMS, main.assist.level, func(i: int) -> void:
		main.set_assist(i)
		build()))
	_switch(c, "Automatic fade-out", "Lessons choose the level and lower it as you improve", main.lessons.auto_assist, func(b: bool) -> void:
		main.lessons.auto_assist = b
		build())
	var sp := [1.0, 0.75, 0.5]
	var cur := 0
	for i in sp.size():
		if absf(main.sim_speed - sp[i]) < 0.01:
			cur = i
	_row(c, "Training speed  (Y)", "Slow motion to learn the hover", _segmented(["100%", "75%", "50%"], cur, func(i: int) -> void:
		main.set_sim_speed(sp[i])
		build(), 64))

func _build_lessons() -> void:
	var L = main.lessons
	if L.active():
		var a := _card("Current lesson")
		var stop := _pill("Stop", false, true)
		stop.pressed.connect(func() -> void: action.emit("lesson_stop"))
		_row(a, L.lesson_title(), "Esc to resume it", stop)
	var ac := _card("Training assist  (H)", ASSIST_DESC[main.assist.level])
	ac.add_child(_segmented(ASSIST_ITEMS, main.assist.level, func(i: int) -> void:
		main.set_assist(i)
		build()))
	for gi in Lessons.GROUPS.size():
		var c := _card(Lessons.GROUPS[gi])
		for l in Lessons.LIST:
			if int(l[3]) != gi:
				continue
			var b: int = L.best(l[0])
			var ba: String = L.best_assisted(l[0])
			var right := HBoxContainer.new()
			right.add_theme_constant_override("separation", 8)
			if b >= 0:
				right.add_child(_chip("best %d" % b, GOOD if b >= 75 else Color(1.0, 0.8, 0.3)))
			elif ba != "":
				right.add_child(_chip(ba, TEXT2))
			if l[0] != "h_mentor":
				var go := _pill("Start")
				go.custom_minimum_size = Vector2(76, 0)
				go.pressed.connect(func() -> void: action.emit("lesson:" + l[0]))
				right.add_child(go)
			var parts: PackedStringArray = str(l[1]).split("  ", false, 1)
			var title: String = (parts[0] + "   " + parts[1].strip_edges()) if parts.size() > 1 else str(l[1])
			_row(c, title, l[2], right)
			if l[0] == "h_mentor":
				var mh := HBoxContainer.new()
				mh.add_theme_constant_override("separation", 8)
				var ml := _label("Start - you fly:", 13, TEXT2)
				ml.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				mh.add_child(ml)
				for it in [["All controls", "all"], ["Cyclic", "cyc"], ["Collective", "coll"], ["Pedals", "ped"]]:
					var mb := _pill(it[0], it[1] == "all")
					mb.pressed.connect(func() -> void: action.emit("mentor:" + it[1]))
					mh.add_child(mb)
				c.add_child(mh)

func _build_weather() -> void:
	var f = main.fdm
	var c := _card("Wind", "Lessons set their own wind and give yours back afterwards.")
	_slider_row(c, "Wind from", 0.0, 359.0, 1.0, f.atmo.wind_from_deg, "%03.0f°", func(v: float) -> void: f.atmo.wind_from_deg = v)
	_slider_row(c, "Wind speed", 0.0, 35.0, 1.0, f.atmo.wind_speed_kt, "%.0f kt", func(v: float) -> void: f.atmo.wind_speed_kt = v)
	_slider_row(c, "Turbulence", 0.0, 1.0, 0.05, f.atmo.gust_intensity, "%.2f", func(v: float) -> void: f.atmo.gust_intensity = v)
	var a := _card("Air")
	_slider_row(a, "Temperature  (ISA ±)", -30.0, 30.0, 1.0, f.atmo.temp_offset_c, "%+.0f °C", func(v: float) -> void: f.atmo.temp_offset_c = v)
	_slider_row(a, "Visibility", 1500.0, 20000.0, 500.0, main.visibility_m, "%.0f m", func(v: float) -> void: main.set_visibility(v))

func _build_settings() -> void:
	var t := _card("Training display and instructor")
	_switch(t, "Outside sight gates  (B)", "Orange gate ahead, blue gate front-right - look out, not at the circle", main.refs.enabled, func(b: bool) -> void: main.refs.enabled = b)
	_switch(t, "Hover guide circle  (G)", "Drift, height and heading on screen", main.show_guide, func(b: bool) -> void: main.show_guide = b)
	_switch(t, "Instructor messages  (F9)", "", main.instructor.enabled, func(b: bool) -> void: main.instructor.enabled = b)
	_switch(t, "Live coaching", "Corrections from your own inputs", main.coach.enabled, func(b: bool) -> void: main.coach.enabled = b)
	_switch(t, "Instructor voice", "Windows text-to-speech", main.instructor.voice, func(b: bool) -> void: main.instructor.voice = b)
	var c := _card("Controls")
	_slider_row(c, "Mouse cyclic sensitivity", 0.2, 3.0, 0.05, main.controls.mouse_sensitivity, "%.2f", func(v: float) -> void: main.controls.mouse_sensitivity = v)
	_switch(c, "Mouse controls the cyclic  (M)", "", main.controls.mouse_cyclic, func(b: bool) -> void: main.controls.mouse_cyclic = b)
	_switch(c, "Invert mouse Y", "Pull the mouse back = forward cyclic", main.controls.invert_mouse_y, func(b: bool) -> void: main.controls.invert_mouse_y = b)
	var jb := _pill("Set up")
	jb.pressed.connect(func() -> void: action.emit("joy"))
	_row(c, "Joystick  (F8)", "Axes, calibration, dead zones", jb)
	var pb := _pill("Open")
	pb.pressed.connect(func() -> void: action.emit("phone"))
	_row(c, "Phone controller  (F10)", "Tilt a phone as the cyclic or collective", pb)
	var g := _card("Graphics and sound")
	_row(g, "Graphics quality  (F7)", "Low is best on integrated graphics", _segmented(["Low", "Medium", "High"], main.preset, func(i: int) -> void:
		main.apply_preset(i)
		build(), 80))
	_slider_row(g, "Sound volume", 0.0, 1.0, 0.05, main.audio.master_volume, "%.2f", func(v: float) -> void: main.audio.master_volume = v)
	var q := _card("", "Educational simulation only. Not an approved training device. Always follow your instructor and the approved Rotorcraft Flight Manual.")
	var qb := _pill("Quit", false, true)
	qb.pressed.connect(func() -> void: action.emit("quit"))
	_row(q, "Quit to desktop", "Settings are saved", qb)

# ------------------------------------------------------------------ open/close
func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	var w := minf(860.0, vs.x - 32.0)
	var h := minf(720.0, vs.y - 32.0)
	root.offset_left = -w * 0.5
	root.offset_right = w * 0.5
	root.offset_top = -h * 0.5
	root.offset_bottom = h * 0.5

func open() -> void:
	_layout()
	build()
	visible = true

func close() -> void:
	visible = false
