extends Control
## Bell 206B-3 style instrument cluster (simplified layout), drawn in code.
## Every needle is driven by the simulation each frame (see main.gd -> panel.v).
## Markings come from the aircraft data file (verified/derived values where available).

const PANEL_SIZE := Vector2(1000, 620)   # M2.30b: proportions of the real 206B-3 panel (photo)
const R := 86.0

var v := {
	"tq": 0.0, "nr": 100.0, "n2": 100.0, "n1": 62.0, "ias": 0.0, "pitch": 0.0, "roll": 0.0,
	"alt_ft": 0.0, "vsi": 0.0, "hdg": 0.0, "low_rpm": false, "horn_test": false, "ball": 0.0,
	"tot": 400.0, "cautions": {}, "eng_oil": 0.0, "trans_oil": 0.0, "fuel_lb": 0.0, "fuel_psi": 0.0,
}
var limits := {
	"nr_on_min": 95.0, "nr_on_max": 100.0, "nr_off_min": 90.0, "nr_off_max": 107.0,
	"tq_mcp": 85.0, "tq_max": 100.0, "n1_max": 105.0, "vne": 130.0,
}
var font: Font
var blink := 0.0

func _ready() -> void:
	font = ThemeDB.fallback_font
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE

func _process(dt: float) -> void:
	blink = fmod(blink + dt, 1.0)
	queue_redraw()

# value -> angle helpers (angle 0 = right, clockwise positive because y is down)
func _ang(val: float, vmin: float, vmax: float, a0: float, a1: float) -> float:
	return deg_to_rad(lerpf(a0, a1, clampf((val - vmin) / (vmax - vmin), 0.0, 1.0)))

func _face(c: Vector2, title: String, ty := 0.48) -> void:
	draw_circle(c, R + 6, Color(0.18, 0.18, 0.19))
	draw_circle(c, R, Color(0.05, 0.05, 0.06))
	draw_string(font, c + Vector2(-R, R * ty), title, HORIZONTAL_ALIGNMENT_CENTER, R * 2, 12, Color(0.85, 0.85, 0.85))

func _arc(c: Vector2, r: float, vmin: float, vmax: float, s: float, e: float, a0: float, a1: float, col: Color, w := 6.0) -> void:
	draw_arc(c, r, _ang(s, vmin, vmax, a0, a1), _ang(e, vmin, vmax, a0, a1), 24, col, w, true)

func _ticks(c: Vector2, vmin: float, vmax: float, step: float, label_step: float, a0: float, a1: float, fmt := "%d", scale := 1.0) -> void:
	var val := vmin
	while val <= vmax + 0.001:
		var a := _ang(val, vmin, vmax, a0, a1)
		var dir := Vector2(cos(a), sin(a))
		var major := is_equal_approx(fmod(val - vmin, label_step), 0.0) or fmod(val - vmin, label_step) < 0.001
		draw_line(c + dir * (R - (14.0 if major else 7.0)), c + dir * (R - 2.0), Color.WHITE, 2.0 if major else 1.0, true)
		if major:
			draw_string(font, c + dir * (R - 27.0) + Vector2(-16, 5), fmt % (val * scale), HORIZONTAL_ALIGNMENT_CENTER, 32, 12, Color.WHITE)
		val += step

func _needle(c: Vector2, a: float, length: float, col: Color, w := 4.0) -> void:
	var dir := Vector2(cos(a), sin(a))
	draw_line(c - dir * 10.0, c + dir * length, col, w, true)
	draw_circle(c, 6.0, Color(0.25, 0.25, 0.25))

func _readout(c: Vector2, text: String, y := 26.0) -> void:
	var box := Rect2(c + Vector2(-30, y - 13), Vector2(60, 18))
	draw_rect(box, Color(0.0, 0.0, 0.0))
	draw_rect(box, Color(0.4, 0.4, 0.4), false, 1.0)
	draw_string(font, box.position + Vector2(0, 14), text, HORIZONTAL_ALIGNMENT_CENTER, 60, 13, Color(0.6, 1.0, 0.6))

## Layout copied from the student's photo of a real Bell 206B-3 panel (M2.30b). The photo's
## grid, measured and scaled to this 1000 x 620 face: a caution/warning strip in the shadow of the
## glareshield across the top; columns A and B = small engine gauges (4 rows); column C = airspeed,
## dual tach, blank (white cover); column D = attitude, heading, clock; column E = altimeter,
## VSI, OAT, with the red handle low on the right. Light grey face, black bezels with mounting
## screws, small knobs and placards like the photo.
const RS := 40.0                 # small gauges are drawn at this radius and scaled
const STRIP_H := 58.0
const FACE := Color(0.60, 0.63, 0.66)
const FACE_DK := Color(0.50, 0.53, 0.56)

func _draw() -> void:
	# glareshield shadow band with the caution panel
	draw_rect(Rect2(Vector2.ZERO, PANEL_SIZE), Color(0.05, 0.05, 0.055))
	# the panel face, light blue-grey, slightly darker towards the bottom
	var face := Rect2(Vector2(6, STRIP_H), Vector2(PANEL_SIZE.x - 12, PANEL_SIZE.y - STRIP_H - 6))
	draw_rect(face, FACE)
	draw_rect(Rect2(face.position + Vector2(0, face.size.y * 0.55), Vector2(face.size.x, face.size.y * 0.45)), Color(FACE_DK, 0.35))
	draw_rect(Rect2(face.position, Vector2(face.size.x, 10)), Color(0, 0, 0, 0.35))   # shadow under the hood
	for sp in [Vector2(20, 76), Vector2(980, 76), Vector2(20, 600), Vector2(980, 600), Vector2(500, 76), Vector2(500, 600)]:
		_screw(sp, 4.0)
	_caution_strip()
	# --- columns A and B: small engine gauges
	var A := 171.0
	var B := 323.0
	var rows := [150.0, 282.0, 410.0, 532.0]
	var sm := 1.35                # small gauge scale (radius 54)
	for c in [Vector2(A, rows[0]), Vector2(A, rows[1]), Vector2(A, rows[2]), Vector2(A, rows[3]), Vector2(B, rows[0]), Vector2(B, rows[1]), Vector2(B, rows[2]), Vector2(B, rows[3])]:
		_mount(c, 56.0)
	_at(Vector2(A, rows[0]), sm, func() -> void: _small(Vector2.ZERO, "TORQUE %", float(v["tq"]), 0, 120, [[0, limits["tq_mcp"], 0], [limits["tq_mcp"], limits["tq_max"], 1], [limits["tq_max"], limits["tq_max"] + 1.5, 2]], 20, "%3.0f"))
	_at(Vector2(A, rows[1]), sm, func() -> void: _small(Vector2.ZERO, "TOT  C x100", float(v.get("tot", 0.0)), 0, 1000, [[300, 738, 0], [738, 810, 1], [810, 816, 2], [921, 927, 2]], 200, "%4.0f", 0.01))
	_at(Vector2(A, rows[2]), sm, func() -> void: _small(Vector2.ZERO, "GAS PROD %", float(v["n1"]), 0, 110, [[60, limits["n1_max"], 0], [limits["n1_max"], limits["n1_max"] + 1.0, 2]], 20, "%5.1f"))
	_at(Vector2(A, rows[3]), sm, func() -> void: _small(Vector2.ZERO, "FUEL  LB x100", float(v.get("fuel_lb", 0.0)), 0, 700, [[0, 134, 1]], 100, "%3.0f", 0.01))
	_at(Vector2(B, rows[0]), sm, func() -> void: _dual_small(Vector2.ZERO, "ENG OIL", float(v.get("eng_oil", 0.0)), 0, 150, [[50, 115, 1], [115, 130, 0], [130, 131.5, 2], [49, 50, 2]], float(v.get("eng_oil_c", 0.0)), 0, 150, [[0, 107, 0], [107, 109, 2]]))
	_at(Vector2(B, rows[1]), sm, func() -> void: _dual_small(Vector2.ZERO, "XMSN OIL", float(v.get("trans_oil", 0.0)), 0, 100, [[30, 50, 0], [50, 70, 1], [70, 71.5, 2], [29, 30, 2]], float(v.get("trans_oil_c", 0.0)), 0, 150, [[15, 110, 0], [110, 112, 2]]))
	_at(Vector2(B, rows[2]), sm, func() -> void: _small(Vector2.ZERO, "FUEL PRESS", float(v.get("fuel_psi", 0.0)), 0, 30, [[4, 30, 0], [3.6, 4.0, 2]], 10, "%2.0f"))
	_at(Vector2(B, rows[3]), sm, func() -> void: _small(Vector2.ZERO, "AMPS", float(v.get("amps", 0.0)), 0, 150, [[0, 105, 0], [105, 150, 1]], 50, "%3.0f"))
	# --- columns C, D, E: flight instruments (big ones are R = 86 drawn, scaled)
	var C := 498.0
	var D := 695.0
	var E := 889.0
	_mount(Vector2(C, 176), 80.0)
	_at(Vector2(C, 176), 0.86, func() -> void: _asi(Vector2.ZERO))
	_mount(Vector2(C, 340), 80.0)
	_at(Vector2(C, 340), 0.86, func() -> void: _tach(Vector2.ZERO))
	_blank(Vector2(C, 500), 62.0)
	_mount(Vector2(D, 166), 82.0)
	_at(Vector2(D, 166), 0.88, func() -> void: _attitude(Vector2.ZERO))
	_mount(Vector2(D, 334), 80.0)
	_at(Vector2(D, 334), 0.86, func() -> void: _hdg(Vector2.ZERO))
	_mount(Vector2(D, 500), 64.0)
	_clock(Vector2(D, 500), 56.0)
	_mount(Vector2(E, 160), 78.0)
	_at(Vector2(E, 160), 0.84, func() -> void: _alt(Vector2.ZERO))
	_mount(Vector2(E, 316), 62.0)
	_at(Vector2(E, 316), 0.64, func() -> void: _vsi(Vector2.ZERO))
	_mount(Vector2(E, 450), 58.0)
	_at(Vector2(E, 450), 1.25, func() -> void: _small(Vector2.ZERO, "OAT  C", float(v.get("oat", 15.0)), -40, 50, [], 20, "%3.0f"))
	# small knobs and switches dotted on the face like the photo
	for k in [Vector2(258, 214), Vector2(258, 470), Vector2(410, 96), Vector2(598, 96), Vector2(598, 420), Vector2(790, 96), Vector2(790, 246), Vector2(410, 590)]:
		draw_circle(k, 9.0, Color(0.08, 0.08, 0.08))
		draw_circle(k + Vector2(-2, -2), 3.0, Color(0.3, 0.3, 0.3))
	# red handle low on the right (photo) and placards
	draw_rect(Rect2(Vector2(842, 528), Vector2(26, 64)), Color(0.7, 0.07, 0.05))
	draw_rect(Rect2(Vector2(838, 520), Vector2(34, 12)), Color(0.45, 0.05, 0.04))
	draw_string(font, Vector2(600, 586), "MINIMUM CREW: ONE PILOT  -  OBSERVE LIMITATIONS IN FLIGHT MANUAL", HORIZONTAL_ALIGNMENT_LEFT, 230, 8, Color(0.15, 0.15, 0.15))
	draw_string(font, Vector2(600, 598), "THIS HELICOPTER MUST BE OPERATED IN COMPLIANCE WITH BHT-206B3-FM-1", HORIZONTAL_ALIGNMENT_LEFT, 230, 7, Color(0.15, 0.15, 0.15))

## Draws f() with its origin at c and scale k (gauges are written around Vector2.ZERO).
func _at(c: Vector2, k: float, f: Callable) -> void:
	draw_set_transform(c, 0.0, Vector2(k, k))
	f.call()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _screw(p: Vector2, r: float) -> void:
	draw_circle(p, r + 1.0, Color(0.25, 0.25, 0.27))
	draw_circle(p, r, Color(0.72, 0.72, 0.74))
	draw_line(p - Vector2(r * 0.7, -r * 0.3), p + Vector2(r * 0.7, -r * 0.3), Color(0.3, 0.3, 0.32), 1.2)

## Round instrument mounting: black flange with 4 screws on the diagonals, like the photo.
func _mount(c: Vector2, r: float) -> void:
	draw_circle(c + Vector2(2, 3), r + 3.0, Color(0, 0, 0, 0.25))
	draw_circle(c, r + 2.0, Color(0.1, 0.1, 0.11))
	for a in [45.0, 135.0, 225.0, 315.0]:
		var d := Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a)))
		_screw(c + d * (r + 9.0), 3.0)

## White blank cover (the empty instrument hole in the photo).
func _blank(c: Vector2, r: float) -> void:
	_mount(c, r)
	draw_circle(c, r, Color(0.93, 0.93, 0.91))
	draw_arc(c, r - 2.0, 0.0, TAU, 40, Color(0.75, 0.75, 0.73), 2.0)

func _clock(c: Vector2, r: float) -> void:
	draw_circle(c, r, Color(0.04, 0.04, 0.05))
	for i in 12:
		var a := deg_to_rad(i * 30.0 - 90.0)
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * (r - 9), c + d * (r - 2), Color.WHITE, 2.0)
		draw_string(font, c + d * (r - 19) + Vector2(-8, 4), str(12 if i == 0 else i), HORIZONTAL_ALIGNMENT_CENTER, 16, 10, Color.WHITE)
	var t := Time.get_time_dict_from_system()
	var hm: float = float(t["hour"] % 12) + float(t["minute"]) / 60.0
	var mm: float = float(t["minute"]) + float(t["second"]) / 60.0
	for hand in [[hm / 12.0, r * 0.5, 4.0], [mm / 60.0, r * 0.78, 2.5], [float(t["second"]) / 60.0, r * 0.85, 1.0]]:
		var a2 := deg_to_rad(hand[0] * 360.0 - 90.0)
		draw_line(c, c + Vector2(cos(a2), sin(a2)) * hand[1], Color.WHITE if hand[2] > 1.0 else Color(1, 0.6, 0.1), hand[2], true)
	draw_circle(c, 3.0, Color(0.3, 0.3, 0.3))
	draw_string(font, c + Vector2(-r, r * 0.55), "CLOCK", HORIZONTAL_ALIGNMENT_CENTER, r * 2, 8, Color(0.8, 0.8, 0.8))

const ARC_COL := [Color(0.1, 0.75, 0.2), Color(0.95, 0.85, 0.1), Color(0.95, 0.1, 0.1)]
## Small round engine gauge (like the two left columns in the photo).
func _small(c: Vector2, title: String, val: float, vmin: float, vmax: float, arcs: Array, label_step: float, fmt: String, lscale := 1.0) -> void:
	var r := RS
	draw_circle(c, r + 4, Color(0.16, 0.16, 0.17))
	draw_circle(c, r, Color(0.04, 0.04, 0.05))
	var a0 := 135.0
	var a1 := 405.0
	for a in arcs:
		draw_arc(c, r - 3, _ang(a[0], vmin, vmax, a0, a1), _ang(a[1], vmin, vmax, a0, a1), 16, ARC_COL[a[2]], 9.0 if a[2] == 2 else 5.0, true)
	var t := vmin
	while t <= vmax + 0.001:
		var a := _ang(t, vmin, vmax, a0, a1)
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * (r - 9), c + d * (r - 1), Color.WHITE, 1.5)
		draw_string(font, c + d * (r - 19) + Vector2(-11, 4), "%d" % int(round(t * lscale)), HORIZONTAL_ALIGNMENT_CENTER, 22, 9, Color.WHITE)
		t += label_step
	var an := _ang(val, vmin, vmax, a0, a1)
	var dn := Vector2(cos(an), sin(an))
	draw_line(c - dn * 5.0, c + dn * (r - 6), Color.WHITE, 3.0, true)
	draw_circle(c, 3.5, Color(0.3, 0.3, 0.3))
	draw_string(font, c + Vector2(-r, r * 0.86), title, HORIZONTAL_ALIGNMENT_CENTER, r * 2, 8, Color(0.92, 0.92, 0.92))
	var box := Rect2(c + Vector2(-20, r * 0.22), Vector2(40, 13))
	draw_rect(box, Color(0, 0, 0))
	draw_string(font, box.position + Vector2(0, 11), fmt % val, HORIZONTAL_ALIGNMENT_CENTER, 40, 10, Color(0.6, 1.0, 0.6))

## Combined pressure (left half, PSI) / temperature (right half, C) gauge, like the 206 oil gauges.
func _dual_small(c: Vector2, title: String, p: float, pmin: float, pmax: float, parcs: Array, tc: float, tmin: float, tmax: float, tarcs: Array) -> void:
	var r := RS
	draw_circle(c, r + 4, Color(0.16, 0.16, 0.17))
	draw_circle(c, r, Color(0.04, 0.04, 0.05))
	# pressure: 225 -> 315 deg on the left (bottom-left up to top), temperature: 315 -> 405 mirrored on the right
	var pa0 := 135.0
	var pa1 := 255.0
	var ta0 := 45.0
	var ta1 := -75.0
	for a in parcs:
		draw_arc(c, r - 3, _ang(a[0], pmin, pmax, pa0, pa1), _ang(a[1], pmin, pmax, pa0, pa1), 10, ARC_COL[a[2]], 9.0 if a[2] == 2 else 5.0, true)
	for a in tarcs:
		draw_arc(c, r - 3, _ang(a[0], tmin, tmax, ta0, ta1), _ang(a[1], tmin, tmax, ta0, ta1), 10, ARC_COL[a[2]], 9.0 if a[2] == 2 else 5.0, true)
	var ap := _ang(p, pmin, pmax, pa0, pa1)
	var at := _ang(tc, tmin, tmax, ta0, ta1)
	for an in [ap, at]:
		var dn := Vector2(cos(an), sin(an))
		draw_line(c + dn * 6.0, c + dn * (r - 6), Color.WHITE, 3.0, true)
	draw_circle(c, 3.5, Color(0.3, 0.3, 0.3))
	draw_string(font, c + Vector2(-r + 4, 4), "PSI", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.8, 0.8, 0.8))
	draw_string(font, c + Vector2(r - 18, 4), "C", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.8, 0.8, 0.8))
	draw_string(font, c + Vector2(-r, r * 0.86), title, HORIZONTAL_ALIGNMENT_CENTER, r * 2, 8, Color(0.92, 0.92, 0.92))
	var box := Rect2(c + Vector2(-30, r * 0.22), Vector2(60, 13))
	draw_rect(box, Color(0, 0, 0))
	draw_string(font, box.position + Vector2(0, 11), "%3.0f  %3.0f" % [p, tc], HORIZONTAL_ALIGNMENT_CENTER, 60, 10, Color(0.6, 1.0, 0.6))

## Caution / warning panel across the top, in the glareshield shadow (photo). Light names from the
## Bell 206B-3 flight manual. Lights the sim drives: ENG OUT, ROTOR LOW RPM, TOT, XMSN OIL PRESS,
## GEN FAIL, FUEL PUMP, HYD PRESS, FUEL LOW. ENG CHIP, XMSN CHIP, T/R CHIP, A/F FUEL FILTER and
## XMSN OIL TEMP exist on the real panel and light on the press-to-test, but no failure drives
## them yet. Red ones blink.
func _caution_strip() -> void:
	var caut: Dictionary = v.get("cautions", {})
	var test: bool = bool(v.get("ctest", false))
	var lamps := [["ENG OUT", "ENG\nOUT", true], ["ROTOR LOW RPM", "ROTOR\nLOW RPM", true], ["TOT", "TOT", true],
		["TRANS OIL PRESS", "XMSN OIL\nPRESS", false], ["XMSN OIL TEMP", "XMSN OIL\nTEMP", false], ["GEN FAIL", "GEN\nFAIL", false],
		["FUEL PUMP", "FUEL\nPUMP", false], ["FUEL LOW", "FUEL\nLOW", false], ["A/F FUEL FILTER", "A/F FUEL\nFILTER", false],
		["HYD PRESS", "HYD\nPRESS", false], ["ENG CHIP", "ENG\nCHIP", false], ["XMSN CHIP", "XMSN\nCHIP", false], ["T/R CHIP", "T/R\nCHIP", false]]
	var w := 66.0
	var gap := 4.0
	var x0 := 40.0
	draw_rect(Rect2(Vector2(x0 - 6, 6), Vector2(lamps.size() * (w + gap) + 8, 46)), Color(0.14, 0.14, 0.15))
	for i in lamps.size():
		var n: String = lamps[i][0]
		var red: bool = lamps[i][2]
		var lit: bool = bool(caut.get(n, test if not caut.has(n) else false))
		if n == "ROTOR LOW RPM" and not caut.has(n):
			lit = bool(v["low_rpm"])
		if lit and red and blink >= 0.6:
			lit = false
		var r := Rect2(Vector2(x0 + i * (w + gap), 10), Vector2(w, 38))
		var on_col := Color(1.0, 0.16, 0.08) if red else Color(1.0, 0.74, 0.1)
		draw_rect(r, on_col if lit else Color(0.09, 0.09, 0.1))
		draw_rect(r, Color(0.32, 0.32, 0.34), false, 1.0)
		var lines: PackedStringArray = str(lamps[i][1]).split("\n")
		for j in lines.size():
			var yy := r.position.y + (22.0 if lines.size() == 1 else 16.0 + j * 13.0)
			var col := Color(0.15, 0.05, 0.0) if lit else (Color(0.75, 0.35, 0.3) if red else Color(0.72, 0.66, 0.5))
			draw_string(font, Vector2(r.position.x, yy), lines[j], HORIZONTAL_ALIGNMENT_CENTER, w, 11, col)
	# master caution / RPM warning lights at the right end (photo: a small unit right of the strip)
	var mx := x0 + lamps.size() * (w + gap) + 14.0
	draw_rect(Rect2(Vector2(mx, 10), Vector2(990 - mx - 6, 38)), Color(0.12, 0.12, 0.13))
	draw_circle(Vector2(mx + (990 - mx - 6) * 0.5, 29), 7.0, Color(0.55, 0.55, 0.57))
	draw_circle(Vector2(mx + (990 - mx - 6) * 0.5, 29), 5.0, Color(0.08, 0.08, 0.08))

func _torque(c: Vector2) -> void:
	_face(c, "TORQUE %")
	var a0 := 135.0
	var a1 := 405.0
	_arc(c, R - 4, 0, 120, 0, limits["tq_mcp"], a0, a1, Color(0.1, 0.75, 0.2))
	_arc(c, R - 4, 0, 120, limits["tq_mcp"], limits["tq_max"], a0, a1, Color(0.95, 0.85, 0.1))
	_arc(c, R - 4, 0, 120, limits["tq_max"], limits["tq_max"] + 1.2, a0, a1, Color(0.95, 0.1, 0.1), 10)
	_ticks(c, 0, 120, 5, 20, a0, a1)
	_needle(c, _ang(v["tq"], 0, 120, a0, a1), R - 10, Color.WHITE)
	_readout(c, "%3.0f" % v["tq"], 44)

func _tach(c: Vector2) -> void:
	_face(c, "N2  ROTOR  %", -0.22)
	var a0 := 135.0
	var a1 := 405.0
	# power-off rotor limits (outer), power-on limits (inner)
	_arc(c, R - 2, 0, 120, limits["nr_off_min"], limits["nr_off_max"], a0, a1, Color(0.1, 0.75, 0.2), 4)
	_arc(c, R - 2, 0, 120, limits["nr_off_max"], limits["nr_off_max"] + 0.8, a0, a1, Color(0.95, 0.1, 0.1), 10)
	_arc(c, R - 10, 0, 120, limits["nr_on_min"], limits["nr_on_max"], a0, a1, Color(0.1, 0.75, 0.2), 6)
	_arc(c, R - 10, 0, 120, limits["nr_on_max"], limits["nr_on_max"] + 0.8, a0, a1, Color(0.95, 0.1, 0.1), 10)
	_ticks(c, 0, 120, 5, 20, a0, a1)
	_needle(c, _ang(v["n2"], 0, 120, a0, a1), R - 34, Color(0.95, 0.95, 0.95), 5)
	_needle(c, _ang(v["nr"], 0, 120, a0, a1), R - 8, Color(1.0, 0.75, 0.2), 3)
	draw_string(font, c + Vector2(-R, 30), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.75, 0.2))
	draw_string(font, c + Vector2(R - 18, 30), "N2", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

func _asi(c: Vector2) -> void:
	_face(c, "AIRSPEED KNOTS", -0.2)
	var a0 := -90.0
	var a1 := 240.0
	_arc(c, R - 4, 0, 150, 0, limits["vne"], a0, a1, Color(0.1, 0.75, 0.2))
	_arc(c, R - 4, 0, 150, limits["vne"], limits["vne"] + 1.5, a0, a1, Color(0.95, 0.1, 0.1), 10)
	_ticks(c, 0, 150, 10, 20, a0, a1)
	_needle(c, _ang(v["ias"], 0, 150, a0, a1), R - 10, Color.WHITE)

func _attitude(c: Vector2) -> void:
	draw_circle(c, R + 6, Color(0.18, 0.18, 0.19))
	var ppd := R / 28.0
	var roll := deg_to_rad(v["roll"])
	var circle := PackedVector2Array()
	for i in 48:
		var a := TAU * i / 48.0
		circle.append(c + Vector2(cos(a), sin(a)) * R)
	draw_colored_polygon(circle, Color(0.25, 0.55, 0.9))
	var hy: float = v["pitch"] * ppd
	var ground := PackedVector2Array([Vector2(-3 * R, hy), Vector2(3 * R, hy), Vector2(3 * R, 4 * R), Vector2(-3 * R, 4 * R)])
	var rot := Transform2D(-roll, c)
	var gw := rot * ground
	for poly in Geometry2D.intersect_polygons(circle, gw):
		draw_colored_polygon(poly, Color(0.55, 0.35, 0.15))
	for k in range(-6, 7):
		if k == 0:
			continue
		var y: float = hy - k * 5.0 * ppd
		var w := 22.0 if k % 2 == 0 else 11.0
		var p0 := rot * Vector2(-w, y)
		var p1 := rot * Vector2(w, y)
		if p0.distance_to(c) < R * 0.85 and p1.distance_to(c) < R * 0.85:
			draw_line(p0, p1, Color.WHITE, 1.5, true)
	var h0 := rot * Vector2(-R, hy)
	var h1 := rot * Vector2(R, hy)
	var hits := Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([h0, h1]), circle)
	for seg in hits:
		draw_polyline(seg, Color.WHITE, 2.0, true)
	# bank scale
	for b in [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60]:
		var a := deg_to_rad(-90.0 + b)
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * (R - 10), c + d * R, Color.WHITE, 2.0)
	var pa := deg_to_rad(-90.0) - roll
	var pd := Vector2(cos(pa), sin(pa))
	var tip := c + pd * (R - 12)
	var side := Vector2(-pd.y, pd.x) * 6.0
	draw_colored_polygon(PackedVector2Array([tip, tip - pd * 12 + side, tip - pd * 12 - side]), Color(1.0, 0.6, 0.1))
	# fixed aircraft symbol
	var org := Color(1.0, 0.6, 0.1)
	draw_line(c + Vector2(-45, 0), c + Vector2(-15, 0), org, 4)
	draw_line(c + Vector2(15, 0), c + Vector2(45, 0), org, 4)
	draw_circle(c, 4, org)
	_ball(c + Vector2(0, R * 0.66))


## Slip indicator (inclinometer): black tube, two lubber lines, the ball. One ball width
## (about 0.06 g here) off centre is a clearly unbalanced flight - "step on the ball".
func _ball(c: Vector2) -> void:
	var w := 92.0
	var h := 16.0
	var tube := Rect2(c - Vector2(w * 0.5, h * 0.5), Vector2(w, h))
	draw_rect(tube, Color(0.02, 0.02, 0.02))
	draw_rect(tube, Color(0.55, 0.55, 0.55), false, 1.0)
	draw_line(c + Vector2(-9, -h * 0.5), c + Vector2(-9, h * 0.5), Color.WHITE, 2.0)
	draw_line(c + Vector2(9, -h * 0.5), c + Vector2(9, h * 0.5), Color.WHITE, 2.0)
	var x := clampf(float(v.get("ball", 0.0)) / 0.06 * 14.0, -w * 0.5 + 7.0, w * 0.5 - 7.0)
	draw_circle(c + Vector2(x, 0.0), 6.5, Color(0.92, 0.92, 0.92))

func _n1(c: Vector2) -> void:
	_face(c, "GAS PROD N1 %")
	var a0 := 135.0
	var a1 := 405.0
	_arc(c, R - 4, 0, 110, 60, limits["n1_max"], a0, a1, Color(0.1, 0.75, 0.2))
	_arc(c, R - 4, 0, 110, limits["n1_max"], limits["n1_max"] + 1.0, a0, a1, Color(0.95, 0.1, 0.1), 10)
	_ticks(c, 0, 110, 5, 10, a0, a1)
	_needle(c, _ang(v["n1"], 0, 110, a0, a1), R - 10, Color.WHITE)
	_readout(c, "%5.1f" % v["n1"], 44)

func _alt(c: Vector2) -> void:
	_face(c, "ALT FEET", 0.3)
	var alt: float = v["alt_ft"]
	for i in 10:
		var a := deg_to_rad(-90.0 + i * 36.0)
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * (R - 14), c + d * (R - 2), Color.WHITE, 2.0)
		draw_string(font, c + d * (R - 27) + Vector2(-8, 5), str(i), HORIZONTAL_ALIGNMENT_CENTER, 16, 14, Color.WHITE)
		for j in range(1, 5):
			var a2 := deg_to_rad(-90.0 + i * 36.0 + j * 7.2)
			var d2 := Vector2(cos(a2), sin(a2))
			draw_line(c + d2 * (R - 7), c + d2 * (R - 2), Color.WHITE, 1.0)
	_readout(c, "%05d" % int(round(alt / 10.0) * 10.0), -32)
	var a_th := deg_to_rad(-90.0 + fmod(alt, 10000.0) / 10000.0 * 360.0)
	var a_hu := deg_to_rad(-90.0 + fmod(alt, 1000.0) / 1000.0 * 360.0)
	_needle(c, a_th, R * 0.5, Color.WHITE, 6)
	_needle(c, a_hu, R - 12, Color.WHITE, 3)
	draw_string(font, c + Vector2(-R, 40), "1013 hPa", HORIZONTAL_ALIGNMENT_CENTER, R * 2, 11, Color(0.7, 0.7, 0.7))

func _vsi(c: Vector2) -> void:
	_face(c, "VERT SPEED", -0.1)
	# 0 at 9 o'clock; up = clockwise to 2000 at 3 o'clock (top half)
	var a0 := 180.0
	var a1 := 360.0
	var val: float = clampf(v["vsi"], -2000.0, 2000.0)
	for t in [-2000, -1500, -1000, -500, 0, 500, 1000, 1500, 2000]:
		var a := deg_to_rad(180.0 + t / 2000.0 * 160.0)
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * (R - 14), c + d * (R - 2), Color.WHITE, 2.0)
		draw_string(font, c + d * (R - 28) + Vector2(-12, 5), str(absi(t) / 100), HORIZONTAL_ALIGNMENT_CENTER, 24, 12, Color.WHITE)
	draw_string(font, c + Vector2(-20, -30), "UP", HORIZONTAL_ALIGNMENT_CENTER, 40, 11, Color(0.8, 0.8, 0.8))
	draw_string(font, c + Vector2(-20, 42), "DOWN", HORIZONTAL_ALIGNMENT_CENTER, 40, 11, Color(0.8, 0.8, 0.8))
	draw_string(font, c + Vector2(-30, 24), "100 FPM", HORIZONTAL_ALIGNMENT_CENTER, 60, 10, Color(0.7, 0.7, 0.7))
	_needle(c, deg_to_rad(180.0 + val / 2000.0 * 160.0), R - 10, Color.WHITE)

func _hdg(c: Vector2) -> void:
	_face(c, "")
	var hdg: float = v["hdg"]
	for i in 72:
		var deg := i * 5.0
		var a := deg_to_rad(deg - hdg - 90.0)
		var d := Vector2(cos(a), sin(a))
		var major := i % 6 == 0
		draw_line(c + d * (R - (14.0 if major else 7.0)), c + d * (R - 2.0), Color.WHITE, 2.0 if major else 1.0)
		if major:
			var lbl := str(int(deg / 10.0))
			match int(deg):
				0: lbl = "N"
				90: lbl = "E"
				180: lbl = "S"
				270: lbl = "W"
			draw_string(font, c + d * (R - 28) + Vector2(-12, 5), lbl, HORIZONTAL_ALIGNMENT_CENTER, 24, 13, Color.WHITE)
	# lubber line and aircraft
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -R + 2), c + Vector2(-7, -R - 8), c + Vector2(7, -R - 8)]), Color(1.0, 0.6, 0.1))
	draw_line(c + Vector2(0, -26), c + Vector2(0, 26), Color(1.0, 0.6, 0.1), 3)
	draw_line(c + Vector2(-20, -6), c + Vector2(20, -6), Color(1.0, 0.6, 0.1), 3)
	draw_line(c + Vector2(-8, 20), c + Vector2(8, 20), Color(1.0, 0.6, 0.1), 3)
	_readout(c, "%03d" % (int(round(hdg)) % 360), 46)
