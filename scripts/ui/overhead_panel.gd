extends CanvasLayer
## Overhead console - circuit breakers (M2.30). Press O (or the OVERHEAD button in the J panel)
## to look up at it; click a breaker to pull it OUT or push it back IN. A pulled breaker shows its
## white collar, like the real one. What each breaker does in the sim is in
## engine_systems.gd BREAKERS; the names the Bell flight manual uses are marked FM.
## The manual has no drawing of the overhead console, so this arrangement is a SIMULATION layout.

signal closed

var systems
var _view: Control
var _hits: Array = []            # [Rect2, breaker name]
var _hover := ""

const GROUP_ORDER := ["ENGINE", "FUEL", "ELECTRICAL", "FLIGHT", "LIGHTS", "AVIONICS"]

func _ready() -> void:
	layer = 9
	visible = false
	_view = Control.new()
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.draw.connect(_draw_panel)
	_view.gui_input.connect(_input_view)
	add_child(_view)

func open() -> void:
	visible = true
	_view.queue_redraw()

func close() -> void:
	visible = false
	closed.emit()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func _process(_dt: float) -> void:
	if visible:
		var vs := _view.get_viewport_rect().size
		var w := minf(vs.x - 32.0, 980.0)
		_view.position = Vector2((vs.x - w) * 0.5, 16.0)
		_view.size = Vector2(w, 340.0)
		_view.queue_redraw()

func _panel_rect() -> Rect2:
	return Rect2(Vector2.ZERO, _view.size)

func _draw_panel() -> void:
	if systems == null:
		return
	_hits.clear()
	var font := ThemeDB.fallback_font
	var r := _panel_rect()
	# console body: dark grey-black, rounded, screws in the corners
	_view.draw_rect(Rect2(r.position + Vector2(4, 6), r.size), Color(0, 0, 0, 0.45))
	_view.draw_rect(r, Color(0.13, 0.13, 0.14))
	_view.draw_rect(r.grow(-6), Color(0.17, 0.17, 0.18))
	_view.draw_rect(r, Color(0.35, 0.35, 0.37), false, 2.0)
	for c in [r.position + Vector2(14, 14), r.position + Vector2(r.size.x - 14, 14), r.end - Vector2(14, 14), Vector2(r.position.x + 14, r.end.y - 14)]:
		_view.draw_circle(c, 4.0, Color(0.55, 0.55, 0.57))
		_view.draw_line(c - Vector2(3, 0), c + Vector2(3, 0), Color(0.25, 0.25, 0.26), 1.5)
	_view.draw_string(font, r.position + Vector2(24, 30), "OVERHEAD CONSOLE  -  CIRCUIT BREAKERS", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.92, 0.92, 0.9))
	_view.draw_string(font, r.position + Vector2(r.size.x - 330, 30), "click = pull OUT / push IN      O = close", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.7, 0.68))
	# groups side by side, breakers in rows of up to 3 under each group label
	var groups := {}
	for b in systems.BREAKERS:
		if not groups.has(b[1]):
			groups[b[1]] = []
		groups[b[1]].append(b)
	var x := r.position.x + 24.0
	var y0 := r.position.y + 56.0
	var col_w := (r.size.x - 48.0) / 6.0
	for g in GROUP_ORDER:
		if not groups.has(g):
			continue
		var list: Array = groups[g]
		_view.draw_string(font, Vector2(x, y0), g, HORIZONTAL_ALIGNMENT_LEFT, col_w - 8.0, 12, Color(1, 1, 1))
		_view.draw_line(Vector2(x, y0 + 5), Vector2(x + col_w - 12.0, y0 + 5), Color(0.9, 0.9, 0.9, 0.6), 1.0)
		var y := y0 + 22.0
		for b in list:
			_breaker(font, Vector2(x + 18.0, y + 14.0), b)
			y += 42.0
		x += col_w
	# footer: what the hovered breaker does + honesty line
	var info := "Hover a breaker to see what pulling it does."
	for b in systems.BREAKERS:
		if b[0] == _hover:
			info = "%s  (%s)  -  pulled: %s" % [b[0], "named in the Bell flight manual" if b[2] == "FM" else ("AB206 flight manual" if b[2] == "AB206 FM" else "typical 206 breaker, not listed in the manual"), b[3]]
	var out: Array = systems.breakers_out()
	_view.draw_string(font, Vector2(r.position.x + 24, r.end.y - 34), info, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 48.0, 12, Color(0.95, 0.85, 0.5))
	_view.draw_string(font, Vector2(r.position.x + 24, r.end.y - 16), ("OUT: " + ", ".join(out)) if not out.is_empty() else "All breakers IN.   Layout: simulation arrangement (the Bell manual has no overhead drawing).", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 48.0, 11, Color(1.0, 0.55, 0.45) if not out.is_empty() else Color(0.65, 0.65, 0.63))

func _breaker(font: Font, c: Vector2, b: Array) -> void:
	var is_in: bool = systems.cb_in(b[0])
	var hot: bool = b[0] == _hover
	# bezel / nut
	_view.draw_circle(c, 11.0, Color(0.55, 0.55, 0.56))
	_view.draw_circle(c, 9.0, Color(0.32, 0.32, 0.33))
	if not is_in:
		# pulled: white collar visible around a raised black cap (drawn bigger)
		_view.draw_circle(c, 8.5, Color(0.97, 0.97, 0.95))
		_view.draw_circle(c + Vector2(0, -1), 6.5, Color(0.05, 0.05, 0.05))
	else:
		_view.draw_circle(c, 7.0, Color(0.07, 0.07, 0.07))
		_view.draw_circle(c + Vector2(-2, -2), 2.0, Color(0.35, 0.35, 0.35))
	if hot:
		_view.draw_arc(c, 13.5, 0.0, TAU, 32, Color(1.0, 0.85, 0.3), 2.0)
	_view.draw_string(font, c + Vector2(18, 5), b[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1) if b[2] != "TYPICAL" else Color(0.82, 0.82, 0.8))
	_view.draw_string(font, c + Vector2(-16, 26), "OUT" if not is_in else "", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.5, 0.4))
	_hits.append([Rect2(c - Vector2(14, 14), Vector2(120, 30)), b[0]])

func _input_view(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = ""
		for h in _hits:
			if (h[0] as Rect2).has_point(event.position):
				_hover = h[1]
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for h in _hits:
			if (h[0] as Rect2).has_point(event.position):
				systems.pull_breaker(h[1], systems.cb_in(h[1]))
				_view.accept_event()
				return
