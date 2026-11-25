extends CanvasLayer
## Overhead console - circuit breakers (M2.30). Press O (or the OVERHEAD button in the J panel, or a
## HOTAS button) to look up at it; click a breaker to pull it OUT or push it back IN. The same face
## (overhead_face.gd) is the texture on the 3D console above the pilot's head.
## The manual has no drawing of the overhead console, so the arrangement is a SIMULATION layout.

signal closed

const Face = preload("res://scripts/ui/overhead_face.gd")

var systems
var _view: Control
var _face

func _ready() -> void:
	layer = 9
	visible = false
	_view = Control.new()
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.draw.connect(_draw_footer)
	add_child(_view)
	_face = Face.new()
	_face.systems = systems
	_face.cols = 6
	_face.mouse_filter = Control.MOUSE_FILTER_STOP
	_face.gui_input.connect(_input_face)
	_view.add_child(_face)

func open() -> void:
	visible = true

func close() -> void:
	visible = false
	closed.emit()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func _process(_dt: float) -> void:
	if not visible:
		return
	var vs := _view.get_viewport_rect().size
	var w := minf(vs.x - 32.0, 940.0)
	var h := 626.0
	var k := minf(1.0, (vs.y - 80.0) / (h + 56.0))
	_view.position = Vector2((vs.x - w * k) * 0.5, 12.0)
	_view.size = Vector2(w, h + 56.0)
	_view.scale = Vector2(k, k)
	_face.size = Vector2(w, h)
	_view.queue_redraw()

func _draw_footer() -> void:
	if systems == null:
		return
	var font := ThemeDB.fallback_font
	var y0: float = _face.size.y
	_view.draw_rect(Rect2(Vector2(0, y0), Vector2(_view.size.x, 56)), Color(0.07, 0.07, 0.075, 0.95))
	var info := "Hover a breaker to see what pulling it does.   Click = pull OUT / push IN.   O = close."
	for b in systems.BREAKERS:
		if b[0] == _face.hover:
			info = "%s  (%s)  -  pulled: %s" % [b[0], "named in the Bell flight manual" if b[2] == "FM" else ("AB206 flight manual" if b[2] == "AB206 FM" else "typical 206 breaker, not in the manual"), b[3]]
	var out: Array = systems.breakers_out()
	_view.draw_string(font, Vector2(16, y0 + 22), info, HORIZONTAL_ALIGNMENT_LEFT, _view.size.x - 32.0, 13, Color(0.95, 0.85, 0.5))
	_view.draw_string(font, Vector2(16, y0 + 44), ("OUT: " + ", ".join(out)) if not out.is_empty() else "All breakers IN.   Arrangement and amp ratings: simulation layout (the Bell manual has no overhead drawing).", HORIZONTAL_ALIGNMENT_LEFT, _view.size.x - 32.0, 12, Color(1.0, 0.55, 0.45) if not out.is_empty() else Color(0.65, 0.65, 0.63))

func _input_face(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_face.hover = ""
		for h in _face.hits:
			if (h[0] as Rect2).has_point(event.position):
				_face.hover = h[1]
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for h in _face.hits:
			if (h[0] as Rect2).has_point(event.position):
				systems.pull_breaker(h[1], systems.cb_in(h[1]))
				_face.accept_event()
				return
