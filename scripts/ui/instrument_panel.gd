extends Control
## Bell 206B-3 style instrument cluster (simplified layout), drawn in code.
## Every needle is driven by the simulation each frame (see main.gd -> panel.v).
## Markings come from the aircraft data file (verified/derived values where available).

const PANEL_SIZE := Vector2(1000, 420)
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

## Layout after the student's photo of a real Bell 206B-3 panel (M2.30): caution/warning strip across
## the top; two left columns of small engine gauges; centre-left airspeed over the dual tach; centre
## attitude over the heading indicator; right altimeter over the VSI; small gauges far right.
const RS := 40.0                 # small engine gauges

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, PANEL_SIZE), Color(0.10, 0.10, 0.11))
	# panel face (light grey like the photo) with a darker glare-shield lip
	draw_rect(Rect2(Vector2(4, 40), PANEL_SIZE - Vector2(8, 44)), Color(0.33, 0.34, 0.36))
	draw_rect(Rect2(Vector2.ZERO, Vector2(PANEL_SIZE.x, 40)), Color(0.07, 0.07, 0.08))
	_caution_strip()
	# left column 1 / column 2: small engine gauges (4 each)
	var c1 := 62.0
	var c2 := 160.0
	var ys := [92.0, 184.0, 276.0, 368.0]
	_small(Vector2(c1, ys[0]), "TORQUE %", float(v["tq"]), 0, 120, [[0, limits["tq_mcp"], 0], [limits["tq_mcp"], limits["tq_max"], 1], [limits["tq_max"], limits["tq_max"] + 1.5, 2]], 20, "%3.0f")
	_small(Vector2(c1, ys[1]), "TOT C x100", float(v.get("tot", 0.0)), 0, 1000, [[300, 738, 0], [738, 810, 1], [810, 816, 2], [921, 927, 2]], 200, "%4.0f", 0.01)
	_small(Vector2(c1, ys[2]), "GAS PROD N1 %", float(v["n1"]), 0, 110, [[60, limits["n1_max"], 0], [limits["n1_max"], limits["n1_max"] + 1.0, 2]], 20, "%5.1f")
	_small(Vector2(c1, ys[3]), "FUEL LB x100", float(v.get("fuel_lb", 0.0)), 0, 700, [[0, 134, 1]], 100, "%3.0f", 0.01)
	_dual_small(Vector2(c2, ys[0]), "ENG OIL", float(v.get("eng_oil", 0.0)), 0, 150, [[50, 115, 1], [115, 130, 0], [130, 131.5, 2], [49, 50, 2]], float(v.get("eng_oil_c", 0.0)), 0, 150, [[0, 107, 0], [107, 109, 2]])
	_dual_small(Vector2(c2, ys[1]), "XMSN OIL", float(v.get("trans_oil", 0.0)), 0, 100, [[30, 50, 0], [50, 70, 1], [70, 71.5, 2], [29, 30, 2]], float(v.get("trans_oil_c", 0.0)), 0, 150, [[15, 110, 0], [110, 112, 2]])
	_small(Vector2(c2, ys[2]), "FUEL PRESS PSI", float(v.get("fuel_psi", 0.0)), 0, 30, [[4, 30, 0], [3.6, 4.0, 2]], 10, "%2.0f")
	_small(Vector2(c2, ys[3]), "AMPS", float(v.get("amps", 0.0)), 0, 150, [[0, 105, 0], [105, 150, 1]], 50, "%3.0f")
	# flight instruments
	_asi(Vector2(318, 132))
	_tach(Vector2(318, 326))
	_attitude(Vector2(530, 132))
	_hdg(Vector2(530, 326))
	_alt(Vector2(742, 132))
	_vsi(Vector2(742, 326))
	# far right: OAT and the label plate
	_small(Vector2(924, 118), "OAT C", float(v.get("oat", 15.0)), -40, 50, [], 20, "%3.0f")
	draw_rect(Rect2(Vector2(872, 196), Vector2(104, 54)), Color(0.12, 0.12, 0.12))
	draw_string(font, Vector2(872, 216), "BELL 206B-3", HORIZONTAL_ALIGNMENT_CENTER, 104, 12, Color(0.85, 0.85, 0.85))
	draw_string(font, Vector2(872, 236), "SIMULATION", HORIZONTAL_ALIGNMENT_CENTER, 104, 10, Color(0.6, 0.6, 0.6))
	# NR horn test / ROTOR LOW RPM readout under the plate
	draw_string(font, Vector2(872, 290), "N1 %5.1f" % float(v["n1"]), HORIZONTAL_ALIGNMENT_CENTER, 104, 12, Color(0.6, 1.0, 0.6))
	draw_string(font, Vector2(872, 310), "TQ %4.0f" % float(v["tq"]), HORIZONTAL_ALIGNMENT_CENTER, 104, 12, Color(0.6, 1.0, 0.6))
	draw_string(font, Vector2(872, 330), "TOT %4.0f" % float(v.get("tot", 0.0)), HORIZONTAL_ALIGNMENT_CENTER, 104, 12, Color(1.0, 0.5, 0.4) if float(v.get("tot", 0.0)) > 810.0 else Color(0.6, 1.0, 0.6))

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

## Caution / warning light strip across the top of the panel (as in the photo). Light names from
## the Bell 206B-3 flight manual (Section 3). Red ones blink.
func _caution_strip() -> void:
	var caut: Dictionary = v.get("cautions", {})
	var names := ["ENG OUT", "ROTOR LOW RPM", "TOT", "TRANS OIL PRESS", "GEN FAIL", "FUEL PUMP", "HYD PRESS", "FUEL LOW"]
	var short := {"ENG OUT": "ENG OUT", "ROTOR LOW RPM": "RTR LOW RPM", "TRANS OIL PRESS": "XMSN OIL PRESS", "GEN FAIL": "GEN FAIL", "FUEL PUMP": "FUEL PUMP", "HYD PRESS": "HYD PRESS", "FUEL LOW": "FUEL LOW", "TOT": "TOT"}
	var w := 92.0
	var x0 := (PANEL_SIZE.x - names.size() * (w + 4.0)) * 0.5
	for i in names.size():
		var n: String = names[i]
		var lit: bool = bool(caut.get(n, v["low_rpm"] if n == "ROTOR LOW RPM" else false))
		var red: bool = n in ["ENG OUT", "ROTOR LOW RPM", "TOT"]
		if lit and red and blink >= 0.6:
			lit = false
		var r := Rect2(Vector2(x0 + i * (w + 4.0), 7.0), Vector2(w, 26))
		var on_col := Color(0.9, 0.1, 0.05) if red else Color(0.98, 0.7, 0.08)
		var off_col := Color(0.2, 0.07, 0.06) if red else Color(0.19, 0.15, 0.07)
		draw_rect(r, on_col if lit else off_col)
		draw_rect(r, Color(0.45, 0.45, 0.45), false, 1.0)
		draw_string(font, r.position + Vector2(0, 17), short[n], HORIZONTAL_ALIGNMENT_CENTER, w, 10, Color(1, 1, 1) if lit else Color(0.5, 0.4, 0.33))

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
