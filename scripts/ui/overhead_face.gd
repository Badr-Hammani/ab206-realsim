extends Control
## Face of the overhead circuit-breaker console (M2.30b), drawn like the real thing: a dark grey
## panel with white engraved group titles and labels, and round black push-pull breaker caps
## with their amp rating, a white collar showing when a breaker is pulled. Used both as the
## texture on the 3D console above the pilot's head and as the clickable O panel.
##
## Breaker names: Bell BHT-206B3-FM-1 where the manual names them (see engine_systems.gd
## BREAKERS). The manual has no drawing of the console, so the arrangement and the amp ratings
## are a SIMULATION layout (typical values for these circuits), not Bell data.

const AMPS := {
	"START": 5, "IGN ENG": 5, "FUEL VALVE": 5, "GOV": 5, "ENG ANTI ICE": 5,
	"FUEL BOOST FWD": 10, "FUEL BOOST AFT": 10, "FUEL QTY": 2,
	"GEN FIELD": 5, "CAUTION LT": 5, "INST LT": 5,
	"HYD BOOST": 5, "PITOT HTR": 10,
	"LDG LT": 20, "ANTI COLL": 5, "NAV LT": 5,
	"COMM": 7, "NAV": 5, "PA SYST": 5,
}
const GROUP_ORDER := ["ENGINE", "FUEL", "ELECTRICAL", "FLIGHT", "LIGHTS", "AVIONICS"]
const PANEL := Color(0.16, 0.16, 0.17)
const ENGRAVE := Color(0.93, 0.93, 0.9)

var systems
var cols := 3                    # breakers per row
var hover := ""
var hits: Array = []             # [Rect2, name] in local coordinates

signal redrawn
var _sig := ""

func _process(_dt: float) -> void:
	if systems == null:
		return
	# redraw only when a breaker or the hover changes (cheap on a laptop)
	var sig := ",".join(systems.breakers_out()) + "|" + hover + "|" + str(size)
	if sig != _sig:
		_sig = sig
		queue_redraw()
		redrawn.emit()

func _draw() -> void:
	if systems == null:
		return
	hits.clear()
	var font := ThemeDB.fallback_font
	var w := size.x
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.07, 0.075))
	draw_rect(Rect2(Vector2(6, 6), size - Vector2(12, 12)), PANEL)
	for c in [Vector2(16, 16), Vector2(w - 16, 16), Vector2(16, size.y - 16), Vector2(w - 16, size.y - 16)]:
		draw_circle(c, 5.0, Color(0.6, 0.6, 0.62))
		draw_line(c - Vector2(3.5, 1), c + Vector2(3.5, 1), Color(0.3, 0.3, 0.32), 1.5)
	draw_string(font, Vector2(0, 40), "CIRCUIT BREAKERS", HORIZONTAL_ALIGNMENT_CENTER, w, 16, ENGRAVE)
	var groups := {}
	for b in systems.BREAKERS:
		if not groups.has(b[1]):
			groups[b[1]] = []
		groups[b[1]].append(b)
	var y := 62.0
	var cell := (w - 40.0) / float(cols)
	for g in GROUP_ORDER:
		if not groups.has(g):
			continue
		# engraved group title with a line each side, like a real console
		var tw := font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, Vector2((w - tw) * 0.5, y + 12), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ENGRAVE)
		draw_line(Vector2(22, y + 7), Vector2((w - tw) * 0.5 - 8, y + 7), ENGRAVE, 1.0)
		draw_line(Vector2((w + tw) * 0.5 + 8, y + 7), Vector2(w - 22, y + 7), ENGRAVE, 1.0)
		y += 22.0
		var list: Array = groups[g]
		for i in list.size():
			var b: Array = list[i]
			var cx := 20.0 + cell * (i % cols) + cell * 0.5
			var cy := y + floorf(i / cols) * 66.0
			_breaker(font, Vector2(cx, cy), cell, b)
		y += ceilf(list.size() / float(cols)) * 66.0 + 6.0

func _breaker(font: Font, top: Vector2, cell: float, b: Array) -> void:
	var name: String = b[0]
	var is_in: bool = systems.cb_in(name)
	# label engraved above the breaker (two lines when long)
	var words := name.split(" ")
	var l1 := name
	var l2 := ""
	if name.length() > 10 and words.size() > 1:
		l1 = " ".join(words.slice(0, words.size() - 1))
		l2 = words[words.size() - 1]
	draw_string(font, top + Vector2(-cell * 0.5, 10), l1, HORIZONTAL_ALIGNMENT_CENTER, cell, 11, ENGRAVE)
	if l2 != "":
		draw_string(font, top + Vector2(-cell * 0.5, 22), l2, HORIZONTAL_ALIGNMENT_CENTER, cell, 11, ENGRAVE)
	var c := top + Vector2(0, 42)
	# hex mounting nut, then the cap
	var nut := PackedVector2Array()
	for k in 6:
		var a := deg_to_rad(30.0 + 60.0 * k)
		nut.append(c + Vector2(cos(a), sin(a)) * 16.0)
	draw_colored_polygon(nut, Color(0.62, 0.62, 0.64))
	draw_polyline(nut + PackedVector2Array([nut[0]]), Color(0.35, 0.35, 0.37), 1.2)
	if is_in:
		draw_circle(c, 11.5, Color(0.04, 0.04, 0.04))
		draw_arc(c, 11.5, deg_to_rad(200), deg_to_rad(320), 10, Color(0.35, 0.35, 0.35), 1.5)
		draw_string(font, c + Vector2(-12, 4), str(AMPS.get(name, 5)), HORIZONTAL_ALIGNMENT_CENTER, 24, 10, Color(0.92, 0.92, 0.92))
	else:
		# pulled: the white collar shows round the raised cap
		draw_circle(c, 13.0, Color(0.98, 0.98, 0.96))
		draw_circle(c + Vector2(0, -2), 10.0, Color(0.04, 0.04, 0.04))
		draw_string(font, c + Vector2(-12, 2), str(AMPS.get(name, 5)), HORIZONTAL_ALIGNMENT_CENTER, 24, 10, Color(0.92, 0.92, 0.92))
	if name == hover:
		draw_arc(c, 18.5, 0.0, TAU, 32, Color(1.0, 0.85, 0.3), 2.0)
	hits.append([Rect2(top - Vector2(cell * 0.5, 0), Vector2(cell, 62)), name])
